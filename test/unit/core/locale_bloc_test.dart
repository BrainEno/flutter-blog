import 'dart:async';

import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory store with optional gates and failure injection.
class _MemoryStore implements LocalePreferenceStore {
  _MemoryStore([this.stored = AppLanguage.system]);

  AppLanguage stored;
  Object? loadError;
  Object? saveError;
  Completer<void>? saveGate;
  final List<AppLanguage> writes = [];

  @override
  Future<AppLanguage> load() async {
    if (loadError != null) throw loadError!;
    return stored;
  }

  @override
  Future<void> save(AppLanguage language) async {
    if (saveGate != null) await saveGate!.future;
    if (saveError != null) throw saveError!;
    writes.add(language);
    stored = language;
  }
}

/// The device locale is read only while following the system; these are plain
/// unit tests, so it is pinned instead of touching a widget binding.
LocaleBloc _bloc(LocalePreferenceStore store) =>
    LocaleBloc(store, deviceLocale: () => const Locale('zh'));

void main() {
  setUp(AppLogger.clearDiagnostics);

  test('the stored choice is applied once the bloc initializes', () async {
    final bloc = _bloc(_MemoryStore(AppLanguage.en));
    addTearDown(bloc.close);
    expect(bloc.state.language, AppLanguage.system);

    await pumpEventQueue();
    expect(bloc.state.language, AppLanguage.en);
    expect(bloc.state.locale, const Locale('en'));
    expect(bloc.state.content, ContentLanguage.en);
  });

  test('without a stored choice the app keeps following the system', () async {
    final bloc = _bloc(_MemoryStore());
    addTearDown(bloc.close);

    await pumpEventQueue();
    expect(bloc.state.language, AppLanguage.system);
    expect(bloc.state.locale, isNull);
    expect(bloc.state.content, ContentLanguage.zh);
  });

  test('the first frame can wait for the stored choice', () async {
    final content = ContentLocale();
    final bloc = LocaleBloc(
      _MemoryStore(AppLanguage.en),
      contentLocale: content,
      deviceLocale: () => const Locale('zh'),
    );
    addTearDown(bloc.close);

    await bloc.initialized;
    // Both the state and the holder are ready: the feed's first request
    // already carries the stored language instead of the default one.
    expect(bloc.state.language, AppLanguage.en);
    expect(content.tag, 'en');
  });

  test('a choice is persisted before it is emitted', () async {
    final store = _MemoryStore();
    final bloc = _bloc(store);
    addTearDown(bloc.close);
    await pumpEventQueue();

    store.saveGate = Completer<void>();
    bloc.add(SetAppLanguage(AppLanguage.zh));
    await pumpEventQueue();
    // The write is still in flight: the interface must not switch before the
    // preference it shows is durable.
    expect(bloc.state.language, AppLanguage.system);

    store.saveGate!.complete();
    await pumpEventQueue();
    expect(bloc.state.language, AppLanguage.zh);
    expect(store.writes, [AppLanguage.zh]);
  });

  test('rapid changes land in order', () async {
    final store = _MemoryStore();
    final bloc = _bloc(store);
    addTearDown(bloc.close);
    await pumpEventQueue();

    store.saveGate = Completer<void>();
    bloc.add(SetAppLanguage(AppLanguage.en));
    bloc.add(SetAppLanguage(AppLanguage.zh));
    await pumpEventQueue();
    // Events are serialized: the second write cannot start (or overtake the
    // first) while the first is still in flight.
    expect(store.writes, isEmpty);

    store.saveGate!.complete();
    await pumpEventQueue();
    expect(store.writes, [AppLanguage.en, AppLanguage.zh]);
    expect(bloc.state.language, AppLanguage.zh);
  });

  test('a failed save still switches the interface', () async {
    final store = _MemoryStore()..saveError = StateError('disk full');
    final bloc = _bloc(store);
    addTearDown(bloc.close);
    await pumpEventQueue();

    bloc.add(SetAppLanguage(AppLanguage.en));
    await pumpEventQueue();
    expect(bloc.state.language, AppLanguage.en);
    expect(bloc.state.locale, const Locale('en'));
    expect(bloc.state.content, ContentLanguage.en);
    expect(
      AppLogger.diagnosticsReport(),
      contains('saving the language preference failed'),
    );
  });

  test('a failed load degrades to following the system', () async {
    final store = _MemoryStore()..loadError = StateError('corrupt database');
    final bloc = _bloc(store);
    addTearDown(bloc.close);

    await pumpEventQueue();
    expect(bloc.state.language, AppLanguage.system);
    expect(
      AppLogger.diagnosticsReport(),
      contains('loading the language preference failed'),
    );
    // The bloc stays usable: the user can still pick a language afterwards.
    bloc.add(SetAppLanguage(AppLanguage.zh));
    await pumpEventQueue();
    expect(bloc.state.language, AppLanguage.zh);
  });

  test('unknown stored values fall back to following the system', () {
    expect(appLanguageFromStorageValue(null), AppLanguage.system);
    expect(appLanguageFromStorageValue('fr'), AppLanguage.system);
    expect(appLanguageFromStorageValue('zh'), AppLanguage.zh);
    expect(appLanguageFromStorageValue('en'), AppLanguage.en);
    expect(localeFor(AppLanguage.zh), const Locale('zh', 'CN'));
    expect(localeFor(AppLanguage.en), const Locale('en'));
    expect(localeFor(AppLanguage.system), isNull);
  });
}
