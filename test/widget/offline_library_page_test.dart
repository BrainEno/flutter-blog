import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/offline_library.dart';
import 'package:belog/features/blog/presentation/blocs/offline_library/offline_library_cubit.dart';
import 'package:belog/features/blog/presentation/pages/offline_library_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/locale_test_support.dart';

class _Repository extends Mock implements BlogRepository {}

OfflineLibrarySnapshot _snapshot(
  String locale, {
  String id = 'rain-story',
  String title = 'Rain title',
  String body = 'A quiet rain falls over the garden.',
}) => OfflineLibrarySnapshot(
  locale: locale,
  summary: const OfflineLibrarySummary(articleCount: 1, estimatedBytes: 2048),
  entries: [
    OfflineLibraryEntry(
      article: Blog(
        id: id,
        title: title,
        content: body,
        posterId: 'writer',
        posterName: 'Avery',
        imageUrl: 'https://image.example.invalid/cover.webp',
        tags: const ['weather'],
        updatedAt: DateTime.utc(2026),
        locale: locale,
      ),
      lastAccessedAt: DateTime.utc(2026),
      estimatedBytes: 2048,
    ),
  ],
);

void main() {
  late _Repository repository;
  late ContentLocale content;
  late LocaleBloc localeBloc;
  late OfflineLibraryCubit cubit;
  late GoRouter router;

  setUp(() async {
    repository = _Repository();
    content = ContentLocale();
    localeBloc = LocaleBloc(
      SystemLocalePreferenceStore(),
      contentLocale: content,
      deviceLocale: () => const Locale('en'),
    );
    // Let the bloc finish its initial system-language event before the page
    // subscribes. Production also waits for this before it builds the router;
    // otherwise that event itself would look like a user language switch.
    await localeBloc.initialized;
    cubit = OfflineLibraryCubit(
      getOfflineLibrary: GetOfflineLibrary(repository),
      clearOfflineLibrary: ClearOfflineLibrary(repository),
      contentLocale: content,
    );
    router = GoRouter(
      initialLocation: '/search/offline-library',
      routes: [
        GoRoute(
          path: '/search/offline-library',
          builder: (context, state) => MultiBlocProvider(
            providers: [
              BlocProvider<LocaleBloc>.value(value: localeBloc),
              BlocProvider<OfflineLibraryCubit>.value(value: cubit),
            ],
            child: const OfflineLibraryPage(),
          ),
          routes: [
            GoRoute(
              path: 'view/:id',
              builder: (context, state) =>
                  Text('viewer:${state.pathParameters['id']}'),
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    await cubit.close();
    await localeBloc.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a local scoped catalog and searches cached body text', (
    tester,
  ) async {
    when(
      () => repository.getOfflineLibrary(),
    ).thenAnswer((_) async => right(_snapshot('en')));

    await pump(tester);

    expect(find.text('Offline library'), findsWidgets);
    expect(find.textContaining('Only the active server'), findsOneWidget);
    expect(find.textContaining('This server · en'), findsOneWidget);
    expect(find.text('Rain title'), findsOneWidget);
    expect(find.text('Avery'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('about 2 KB'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'quiet garden');
    await tester.pump();
    expect(find.textContaining('Matched cached text'), findsOneWidget);
    expect(
      find.textContaining('quiet rain falls over the garden'),
      findsOneWidget,
    );
    verify(() => repository.getOfflineLibrary()).called(1);
  });

  testWidgets(
    'reports a local query error without replacing the visible cache',
    (tester) async {
      when(
        () => repository.getOfflineLibrary(),
      ).thenAnswer((_) async => right(_snapshot('en')));

      await pump(tester);
      await tester.enterText(find.byType(TextField), '"unfinished');
      await tester.pump();

      expect(
        find.text('Close the quoted phrase before searching.'),
        findsOneWidget,
      );
      expect(find.text('Rain title'), findsNothing);
      verify(() => repository.getOfflineLibrary()).called(1);
    },
  );

  testWidgets('opening a cached result stays on the current search branch', (
    tester,
  ) async {
    when(
      () => repository.getOfflineLibrary(),
    ).thenAnswer((_) async => right(_snapshot('en')));

    await pump(tester);
    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('Open cached article: Rain title'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }

    await tester.tap(find.text('Rain title'));
    await tester.pumpAndSettle();

    expect(find.text('viewer:rain-story'), findsOneWidget);
  });

  testWidgets(
    'confirmed clear reloads the scoped catalog rather than other data',
    (tester) async {
      var reads = 0;
      when(() => repository.getOfflineLibrary()).thenAnswer((_) async {
        reads++;
        return right(
          reads == 1
              ? _snapshot('en')
              : OfflineLibrarySnapshot.empty(locale: 'en'),
        );
      });
      when(
        () => repository.clearOfflineLibrary(),
      ).thenAnswer((_) async => right(null));

      await pump(tester);
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Clear this offline library?'), findsOneWidget);

      await tester.tap(find.text('Clear cached articles'));
      await tester.pumpAndSettle();

      expect(find.text('No cached articles in this language'), findsOneWidget);
      verify(() => repository.clearOfflineLibrary()).called(1);
      expect(reads, 2);
    },
  );

  testWidgets(
    'content language changes clear old results before loading new scope',
    (tester) async {
      when(() => repository.getOfflineLibrary()).thenAnswer((_) async {
        return right(
          content.tag == 'en'
              ? _snapshot('en', id: 'english')
              : _snapshot('zh-CN', id: 'chinese'),
        );
      });

      await pump(tester);
      expect(find.text('Rain title'), findsOneWidget);
      localeBloc.add(SetAppLanguage(AppLanguage.zh));
      await tester.pumpAndSettle();

      expect(content.tag, 'zh-CN');
      expect(cubit.state.snapshot?.locale, 'zh-CN');
      expect(cubit.state.snapshot?.entries.single.article.id, 'chinese');
    },
  );
}
