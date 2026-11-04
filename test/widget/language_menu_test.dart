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
    // A Chinese device makes the default ("follow system") state
    // deterministic regardless of the machine running the suite.
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, label),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the menu offers system, Chinese and English', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    // Exactly the active choice is ticked.
    expect(find.byIcon(Icons.done), findsOneWidget);
  });

  testWidgets('picking English switches the interface and persists it', (
    tester,
  ) async {
    final bloc = await pumpMenu(tester);
    expect(bloc.state.language, AppLanguage.system);

    await openMenu(tester);
    await pick(tester, 'English');

    expect(bloc.state.language, AppLanguage.en);
    final english = Localizations.localeOf(
      find.byType(Scaffold).evaluate().single,
    );
    expect(english.languageCode, 'en');
  });

  testWidgets('picking Chinese pins the interface to Chinese', (tester) async {
    final bloc = await pumpMenu(tester);

    await openMenu(tester);
    await pick(tester, '中文');

    expect(bloc.state.language, AppLanguage.zh);
    final chinese = Localizations.localeOf(
      find.byType(Scaffold).evaluate().single,
    );
    expect(chinese.languageCode, 'zh');
  });
}
