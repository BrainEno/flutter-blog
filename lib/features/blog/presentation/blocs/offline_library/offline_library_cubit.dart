import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library_query.dart';
import 'package:belog/features/blog/domain/usecase/offline_library.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Page-scoped state for the device-only Offline Library.
///
/// It keeps a bounded snapshot in memory while a reader changes query text, so
/// every keystroke is a pure in-memory match rather than a fresh SQLite scan.
/// Reads and clears are fenced by a generation *and* the active content locale:
/// a delayed English response cannot be painted onto a Chinese library after a
/// language switch.
class OfflineLibraryCubit extends Cubit<OfflineLibraryState> {
  OfflineLibraryCubit({
    required GetOfflineLibrary getOfflineLibrary,
    required ClearOfflineLibrary clearOfflineLibrary,
    required ContentLocale contentLocale,
  }) : _getOfflineLibrary = getOfflineLibrary,
       _clearOfflineLibrary = clearOfflineLibrary,
       _contentLocale = contentLocale,
       super(OfflineLibraryState.initial(locale: contentLocale.tag));

  final GetOfflineLibrary _getOfflineLibrary;
  final ClearOfflineLibrary _clearOfflineLibrary;
  final ContentLocale _contentLocale;

  int _generation = 0;
  String _queryText = '';

  /// Reads the current local namespace for initial entry, pull-to-refresh, or
  /// a language event; no connection check or HTTP request is involved.
  ///
  /// A refresh may retain same-scope results while SQLite is reading. A
  /// successful clear passes [retainSnapshot] as false: rendering rows known to
  /// have been deleted would be a worse failure mode than showing a brief local
  /// loading state if the confirmation read cannot finish.
  Future<void> load({bool retainSnapshot = true}) async {
    final locale = _contentLocale.tag;
    final generation = ++_generation;
    final previous = state.snapshot;
    // Keeping an already-loaded snapshot is pleasant on an ordinary refresh,
    // but showing it across a language change would leak the wrong edition.
    final visibleSnapshot = retainSnapshot && previous?.locale == locale
        ? previous
        : null;
    emit(
      _stateFor(
        snapshot: visibleSnapshot,
        locale: locale,
        isLoading: true,
        clearFailure: null,
      ),
    );

    final result = await _getOfflineLibrary(NoParams());
    if (isClosed || generation != _generation) return;
    if (locale != _contentLocale.tag) {
      // The datasource captured [locale] before awaiting SQLite. Start a new
      // read rather than displaying a now-invalid response.
      await load();
      return;
    }
    result.fold(
      (failure) => emit(
        _stateFor(
          snapshot: visibleSnapshot,
          locale: locale,
          isLoading: false,
          loadFailure: failure.forPresentation(),
        ),
      ),
      (snapshot) {
        // Implementations must carry the same scope they read. Treat a broken
        // adapter as a storage error rather than relabeling another locale.
        if (snapshot.locale != locale ||
            snapshot.entries.any((entry) => entry.article.locale != locale)) {
          emit(
            _stateFor(
              snapshot: null,
              locale: locale,
              isLoading: false,
              loadFailure: Failure.storage(
                cause: StateError('Offline library returned another locale.'),
              ),
            ),
          );
          return;
        }
        emit(_stateFor(snapshot: snapshot, locale: locale, isLoading: false));
      },
    );
  }

  /// Changes the in-memory query. Invalid input is represented explicitly and
  /// does not scan database rows or make a network call.
  void setQuery(String value) {
    _queryText = value;
    final snapshot = state.snapshot;
    emit(
      _stateFor(
        snapshot: snapshot,
        locale: state.locale,
        isLoading: state.isLoading,
        isClearing: state.isClearing,
        loadFailure: state.loadFailure,
        clearFailure: state.clearFailure,
      ),
    );
  }

  /// Drops only this backend/locale cache after the screen received explicit
  /// user confirmation. A concurrent language change leaves the original
  /// namespace operation intact but never applies its completion to the new
  /// language's state.
  Future<void> clear() async {
    final snapshot = state.snapshot;
    final locale = _contentLocale.tag;
    if (snapshot == null || snapshot.locale != locale || state.isClearing) {
      return;
    }
    final generation = ++_generation;
    emit(
      _stateFor(
        snapshot: snapshot,
        locale: locale,
        isClearing: true,
        loadFailure: state.loadFailure,
      ),
    );
    final result = await _clearOfflineLibrary(NoParams());
    if (isClosed || generation != _generation) return;
    if (locale != _contentLocale.tag) {
      // A clear is scoped by the datasource at invocation. Its completion is
      // irrelevant to a newly selected language, which gets a fresh read.
      await load();
      return;
    }
    final didClear = result.fold((failure) {
      emit(
        _stateFor(
          snapshot: snapshot,
          locale: locale,
          isClearing: false,
          clearFailure: failure.forPresentation(),
        ),
      );
      return false;
    }, (_) => true);
    if (didClear) {
      // Querying again rather than manufacturing an empty state accounts for
      // a legitimate cache write that may have completed during the clear.
      await load(retainSnapshot: false);
    }
  }

  OfflineLibraryState _stateFor({
    required OfflineLibrarySnapshot? snapshot,
    required String locale,
    bool isLoading = false,
    bool isClearing = false,
    Failure? loadFailure,
    Failure? clearFailure,
  }) {
    final trimmed = _queryText.trim();
    if (trimmed.isEmpty) {
      return OfflineLibraryState(
        locale: locale,
        snapshot: snapshot,
        queryText: _queryText,
        isLoading: isLoading,
        isClearing: isClearing,
        loadFailure: loadFailure,
        clearFailure: clearFailure,
      );
    }

    final parsed = OfflineLibraryQuery.parse(_queryText);
    if (!parsed.isValid || snapshot == null) {
      return OfflineLibraryState(
        locale: locale,
        snapshot: snapshot,
        queryText: _queryText,
        queryIssue: parsed.issue,
        isLoading: isLoading,
        isClearing: isClearing,
        loadFailure: loadFailure,
        clearFailure: clearFailure,
      );
    }
    return OfflineLibraryState(
      locale: locale,
      snapshot: snapshot,
      queryText: _queryText,
      query: parsed.query,
      results: parsed.query!.search(snapshot.entries),
      isLoading: isLoading,
      isClearing: isClearing,
      loadFailure: loadFailure,
      clearFailure: clearFailure,
    );
  }
}

/// Immutable presentation state. [snapshot] is null while a different locale
/// is loading or after a local storage error, which keeps stale cached rows out
/// of the screen rather than silently showing the wrong language.
class OfflineLibraryState {
  const OfflineLibraryState({
    required this.locale,
    this.snapshot,
    this.queryText = '',
    this.query,
    this.queryIssue,
    this.results = const [],
    this.isLoading = false,
    this.isClearing = false,
    this.loadFailure,
    this.clearFailure,
  });

  factory OfflineLibraryState.initial({required String locale}) =>
      OfflineLibraryState(locale: locale, isLoading: true);

  final String locale;
  final OfflineLibrarySnapshot? snapshot;
  final String queryText;
  final OfflineLibraryQuery? query;
  final OfflineLibraryQueryIssue? queryIssue;
  final List<OfflineLibrarySearchResult> results;
  final bool isLoading;
  final bool isClearing;
  final Failure? loadFailure;
  final Failure? clearFailure;

  bool get hasQuery => queryText.trim().isNotEmpty;
  bool get hasValidQuery => query != null;
  bool get hasLoadFailure => loadFailure != null;

  /// The articles that an unfiltered catalog renders. Search result rows are
  /// held separately because they need the matched-field/excerpt metadata.
  List<OfflineLibraryEntry> get catalogEntries => snapshot?.entries ?? const [];
}
