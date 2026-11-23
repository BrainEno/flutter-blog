import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/domain/repositories/recent_search_store.dart';
import 'package:flutter/foundation.dart';

/// The signed-in reader's recent searches, newest first, for the search page
/// to offer again while its field is empty.
///
/// It follows the signed-in account like the reading marks do: an account
/// change drops the previous reader's list at once and reads the next one's;
/// a guest has none and nothing is recorded for them, so a shared device
/// never shows one person's searches to another, or carries a guest's into
/// an account.
///
/// Changes apply in memory first and are written behind, one after another,
/// so the list on screen never waits for storage. Storage failures are logged
/// and otherwise ignored: the list still works for this session.
class RecentSearches extends ChangeNotifier {
  RecentSearches(this._store, {required AppUserCubit users}) {
    _subscription = users.stream.listen(_follow);
    _follow(users.state);
  }

  final RecentSearchStore _store;
  late final StreamSubscription<AppUserState> _subscription;

  String? _userId;

  /// Bumped on every account change, so a slow read for the previous account
  /// cannot land in the next one's list.
  int _generation = 0;
  List<String> _queries = const [];

  /// What changed since the current account's read began: whether anything
  /// did, whether the list was emptied, and which searches were removed.
  bool _changedSinceLoad = false;
  bool _clearedSinceLoad = false;
  final Set<String> _forgottenSinceLoad = {};
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  /// The searches to offer, newest first; empty for a guest.
  List<String> get queries => _queries;

  void _follow(AppUserState state) {
    final userId = state is AppUserLoggedIn && state.user.id.isNotEmpty
        ? state.user.id
        : null;
    if (userId == _userId) return;
    _userId = userId;
    final generation = ++_generation;
    _changedSinceLoad = false;
    _clearedSinceLoad = false;
    _forgottenSinceLoad.clear();
    if (_queries.isNotEmpty) {
      _queries = const [];
      notifyListeners();
    }
    if (userId == null) return;
    // Writes queue behind the read: a search saved before the stored list
    // is read would otherwise overwrite it, and the merge below would find
    // nothing left to merge.
    final loading = _load(userId, generation);
    _writes = _writes.then((_) => loading);
  }

  Future<void> _load(String userId, int generation) async {
    final List<String> saved;
    try {
      saved = await _store.load(userId: userId);
    } catch (e, stackTrace) {
      AppLogger.error(
        'reading recent searches failed',
        error: e,
        stackTrace: stackTrace,
      );
      return;
    }
    if (_disposed || generation != _generation) return;
    if (!_changedSinceLoad) {
      if (saved.isEmpty) return;
      _queries = List.unmodifiable(saved);
      notifyListeners();
      return;
    }
    // Something was searched, removed or cleared while the read was in
    // flight: that is newer than what was saved, so it stays on top, the
    // saved searches fill in below it, and what was removed or cleared
    // stays gone.
    if (_clearedSinceLoad) return;
    final kept = {for (final entry in _queries) recentSearchKey(entry)};
    final merged = [
      ..._queries,
      for (final query in saved)
        if (!kept.contains(recentSearchKey(query)) &&
            !_forgottenSinceLoad.contains(recentSearchKey(query)))
          query,
    ];
    _apply(userId, rememberAll(merged));
  }

  /// [queries] capped the same way a new search is.
  @visibleForTesting
  static List<String> rememberAll(List<String> queries) {
    var result = const <String>[];
    for (final query in queries.reversed) {
      result = rememberSearch(result, query);
    }
    return result;
  }

  /// Puts [query] on top of the list (a guest's searches are not kept).
  void remember(String query) {
    final userId = _userId;
    if (_disposed || userId == null || query.trim().isEmpty) return;
    _apply(userId, rememberSearch(_queries, query));
  }

  /// Takes [query] off the list.
  void remove(String query) {
    final userId = _userId;
    if (_disposed || userId == null) return;
    _forgottenSinceLoad.add(recentSearchKey(query));
    _apply(userId, forgetSearch(_queries, query));
  }

  /// Empties the list.
  void clear() {
    final userId = _userId;
    if (_disposed || userId == null) return;
    _clearedSinceLoad = true;
    _apply(userId, const []);
  }

  /// Brings back [queries] (what [clear] removed) under anything searched
  /// since, for an undo.
  void restore(List<String> queries) {
    final userId = _userId;
    if (_disposed || userId == null) return;
    _apply(userId, rememberAll([..._queries, ...queries]));
  }

  void _apply(String userId, List<String> next) {
    _changedSinceLoad = true;
    if (!listEquals(next, _queries)) {
      _queries = List.unmodifiable(next);
      notifyListeners();
    }
    final snapshot = _queries;
    _writes = _writes.then((_) => _save(userId, snapshot));
  }

  Future<void> _save(String userId, List<String> queries) async {
    try {
      await _store.save(userId: userId, queries: queries);
    } catch (e, stackTrace) {
      AppLogger.error(
        'saving recent searches failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Completes once every change made so far has been written (or failed).
  @visibleForTesting
  Future<void> get settled => _writes;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
