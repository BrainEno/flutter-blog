import 'package:belog/core/common/widgets/language_menu_button.dart';
import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements LocalePreferenceStore {
  AppLanguage stored = AppLanguage.system;

  @override
  Future<AppLanguage> load() async => stored;

  @override
  Future<void> save(AppLanguage language) async {
    stored = language;
  }
}

void main() {
  Future<LocaleBloc> pumpMenu(WidgetTester tester) async {
    // A Chinese device makes the default ("follow system") assertions
    // deterministic regardless of the machine running the suite.
    tester.platformDispatcher.localeTestValue = const Locale('zh');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final bloc = LocaleBloc(_MemoryStore());
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<LocaleBloc>.value(
        value: bloc,
        child: BlocBuilder<LocaleBloc, LocaleState>(
          builder: (context, state) => MaterialApp(
            locale: state.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en')],
            home: Scaffold(
              appBar: AppBar(
                title: const Text('No Wave'),
                actions: const [LanguageMenuButton()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  testWidgets('the menu offers system, Chinese and English', (tester) async {
    await pumpMenu(tester);

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    // The active choice is ticked.
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('picking English switches the bloc and persists the choice', (
    tester,
  ) async {
    final bloc = await pumpMenu(tester);
    expect(bloc.state.language, AppLanguage.system);

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(bloc.state.language, AppLanguage.en);
    // The interface follows: Material chrome is now English.
    expect(
      Localizations.localeOf(
        tester.element(find.byType(Scaffold)),
      ).languageCode,
      'en',
    );
  });

  testWidgets('picking Chinese pins the interface to zh-CN', (tester) async {
    final bloc = await pumpMenu(tester);

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();

    expect(bloc.state.language, AppLanguage.zh);
    expect(
      Localizations.localeOf(
        tester.element(find.byType(Scaffold)),
      ).languageCode,
      'zh',
    );
  });
}
