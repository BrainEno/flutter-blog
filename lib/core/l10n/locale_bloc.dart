import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LocaleState {
  final AppLanguage language;
  const LocaleState(this.language);

  /// The locale handed to `MaterialApp.locale`; null follows the device.
  Locale? get locale => localeFor(language);

  @override
  bool operator ==(Object other) =>
      other is LocaleState && other.language == language;

  @override
  int get hashCode => language.hashCode;
}

sealed class LocaleEvent {}

class InitializeLocale extends LocaleEvent {}

class SetAppLanguage extends LocaleEvent {
  final AppLanguage language;
  SetAppLanguage(this.language);
}

/// Owns the in-app language setting (issue #108).
///
/// The chosen language is persisted before it is emitted, and events are
/// serialized: a slow read at startup or a slow write must never overwrite a
/// newer choice, and rapid changes must land in the order the user made them.
class LocaleBloc extends Bloc<LocaleEvent, LocaleState> {
  final LocalePreferenceStore _store;

  LocaleBloc(this._store) : super(const LocaleState(AppLanguage.system)) {
    on<LocaleEvent>(
      _onLocaleEvent,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    add(InitializeLocale());
  }

  Future<void> _onLocaleEvent(
    LocaleEvent event,
    Emitter<LocaleState> emit,
  ) async {
    if (event is InitializeLocale) {
      emit(LocaleState(await _loadStoredLanguage()));
      return;
    }
    if (event is! SetAppLanguage) return;

    // The interface follows the tap even when the write fails: a preference
    // that cannot be persisted must not feel like a dead button. The next
    // launch falls back to the last persisted value.
    try {
      await _store.save(event.language);
    } catch (error, stackTrace) {
      AppLogger.error(
        'saving the language preference failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    emit(LocaleState(event.language));
  }

  /// A storage failure degrades to "follow the system" instead of leaving the
  /// app with no state to build from.
  Future<AppLanguage> _loadStoredLanguage() async {
    try {
      return await _store.load();
    } catch (error, stackTrace) {
      AppLogger.error(
        'loading the language preference failed',
        error: error,
        stackTrace: stackTrace,
      );
      return AppLanguage.system;
    }
  }
}
