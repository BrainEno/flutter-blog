import 'dart:async';

import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LocaleState {
  final AppLanguage language;

  /// The content language the same choice implies (issue #108). The interface
  /// and the article requests never disagree.
  final ContentLanguage content;

  const LocaleState(this.language, this.content);

  /// The locale handed to `MaterialApp.locale`; null follows the device.
  Locale? get locale => localeFor(language);

  @override
  bool operator ==(Object other) =>
      other is LocaleState &&
      other.language == language &&
      other.content == content;

  @override
  int get hashCode => Object.hash(language, content);
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

  /// Where new requests read the content language from.
  final ContentLocale _contentLocale;

  /// The device locale, used only while following the system.
  final Locale Function() _deviceLocale;

  /// Completes once the persisted choice has been applied, so the very first
  /// frame can wait for it instead of starting the feed in the wrong language.
  final Completer<void> _initialized = Completer<void>();

  /// Resolves after the stored choice reached both the state and the holder.
  Future<void> get initialized => _initialized.future;

  LocaleBloc(
    this._store, {
    ContentLocale? contentLocale,
    Locale Function()? deviceLocale,
  }) : _contentLocale = contentLocale ?? ContentLocale.instance,
       _deviceLocale =
           deviceLocale ??
           (() => WidgetsBinding.instance.platformDispatcher.locale),
       super(const LocaleState(AppLanguage.system, ContentLanguage.zh)) {
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
      try {
        _emitLanguage(emit, await _loadStoredLanguage());
      } finally {
        if (!_initialized.isCompleted) _initialized.complete();
      }
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
    _emitLanguage(emit, event.language);
  }

  /// Publishes the content language before the interface rebuilds, so the
  /// requests a rebuilt page fires already carry the new `locale`.
  void _emitLanguage(Emitter<LocaleState> emit, AppLanguage language) {
    final content = contentLanguageFor(language, _deviceLocale());
    _contentLocale.update(content);
    emit(LocaleState(language, content));
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
