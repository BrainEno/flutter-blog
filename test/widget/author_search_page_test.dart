import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:belog/features/user/presentation/bloc/author_search/author_search_cubit.dart';
import 'package:belog/features/user/presentation/pages/author_search_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

typedef Result = Either<Failure, List<AuthorSearchResult>>;

class ScriptedRepository implements AuthorSearchRepository {
  final queries = <String>[];
  final requests = <Completer<Result>>[];

  @override
  Future<Result> search(String query) {
    queries.add(query);
    final request = Completer<Result>();
    requests.add(request);
    return request.future;
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required AuthorSearchCubit cubit,
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  final router = GoRouter(
    initialLocation: '/search/authors',
    routes: [
      GoRoute(
        path: '/search/authors',
        builder: (_, _) => BlocProvider<AuthorSearchCubit>.value(
          value: cubit,
          child: const AuthorSearchPage(),
        ),
      ),
      GoRoute(
        path: '/search/author/:userId',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('profile: ${state.pathParameters['userId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightThemeMode,
      darkTheme: AppTheme.darkThemeMode,
      themeMode: mode,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'debounces, invalidates old results immediately, and retries failures',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = ScriptedRepository();
        final cubit = AuthorSearchCubit(
          searchAuthors: SearchAuthors(repository),
        );
        addTearDown(cubit.close);
        await _pumpPage(tester, cubit: cubit);
        expect(
          find.text('Type a name or user ID to find authors'),
          findsOneWidget,
        );

        await tester.enterText(find.byType(TextField), 'old');
        await tester.pump(const Duration(milliseconds: 299));
        expect(repository.queries, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(repository.queries, ['old']);
        expect(find.bySemanticsLabel('Searching…'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'new');
        repository.requests[0].complete(
          right([
            const AuthorSearchResult(userId: 'old', displayName: 'Stale'),
          ]),
        );
        await tester.pump();
        expect(find.text('Stale'), findsNothing);
        expect(find.bySemanticsLabel('Searching…'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        expect(repository.queries, ['old', 'new']);
        repository.requests[1].complete(left(Failure.networkOffline()));
        await tester.pumpAndSettle();
        expect(find.textContaining('No network connection'), findsOneWidget);
        expect(find.text('No matching authors'), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(repository.queries, ['old', 'new', 'new']);
        repository.requests[2].complete(
          right([
            const AuthorSearchResult(
              userId: 'reader',
              displayName: 'Reader',
              bio: 'Bio',
            ),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reader'), findsOneWidget);
        expect(find.text('Bio'), findsOneWidget);
        expect(find.bySemanticsLabel('Avatar of Reader'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(
          find.text('Type a name or user ID to find authors'),
          findsOneWidget,
        );
        expect(repository.queries, hasLength(3));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('too-long UTF-16 query is explained without a network call', (
    tester,
  ) async {
    final repository = ScriptedRepository();
    final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
    addTearDown(cubit.close);
    await _pumpPage(tester, cubit: cubit);
    await tester.enterText(find.byType(TextField), '🌊' * 51);
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Search is too long; shorten it and try again'),
      findsOneWidget,
    );
    expect(repository.queries, isEmpty);
    final overlongAscii = 'x' * 101;
    await tester.enterText(find.byType(TextField), overlongAscii);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      overlongAscii,
    );
    expect(
      find.text('Search is too long; shorten it and try again'),
      findsOneWidget,
    );
    expect(repository.queries, isEmpty);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Type a name or user ID to find authors'), findsOneWidget);
    expect(repository.queries, isEmpty);
  });

  testWidgets('leaving during debounce cancels the scheduled search', (
    tester,
  ) async {
    final repository = ScriptedRepository();
    final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
    addTearDown(cubit.close);
    await _pumpPage(tester, cubit: cubit);
    await tester.enterText(find.byType(TextField), 'writer');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(repository.queries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard search submits immediately without a duplicate timer', (
    tester,
  ) async {
    final repository = ScriptedRepository();
    final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
    addTearDown(cubit.close);
    await _pumpPage(tester, cubit: cubit);
    await tester.enterText(find.byType(TextField), 'writer');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(repository.queries, ['writer']);
    repository.requests.single.complete(right([]));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repository.queries, ['writer']);
    expect(find.text('No matching authors'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('capped results, semantics and 2x text: $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final repository = ScriptedRepository();
          final cubit = AuthorSearchCubit(
            searchAuthors: SearchAuthors(repository),
          );
          addTearDown(cubit.close);
          await _pumpPage(
            tester,
            cubit: cubit,
            locale: locale,
            mode: mode,
            textScale: 2,
          );
          await tester.enterText(find.byType(TextField), 'writer');
          await tester.pump(const Duration(milliseconds: 300));
          repository.requests.single.complete(
            right(
              List.generate(
                100,
                (i) => AuthorSearchResult(
                  userId: 'writer-$i',
                  displayName: i == 0 ? '' : 'Writer $i',
                  bio: i == 0 ? 'A public biography' : '',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = lookupAppLocalizations(locale);
          expect(find.text(l10n.authorSearchLimitNotice), findsOneWidget);
          expect(find.text(l10n.anonymousAuthor), findsOneWidget);
          expect(
            find.bySemanticsLabel(l10n.avatarOf(l10n.anonymousAuthor)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'empty results and encoded author navigation retain the search on back',
    (tester) async {
      final repository = ScriptedRepository();
      final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
      addTearDown(cubit.close);
      await _pumpPage(tester, cubit: cubit);
      await tester.enterText(find.byType(TextField), 'unknown');
      await tester.pump(const Duration(milliseconds: 300));
      repository.requests[0].complete(right([]));
      await tester.pumpAndSettle();
      expect(find.text('No matching authors'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'writer');
      await tester.pump(const Duration(milliseconds: 300));
      const id = 'writer/name?ref=1#%中';
      repository.requests[1].complete(
        right([const AuthorSearchResult(userId: id, displayName: 'Writer')]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Writer'));
      await tester.pumpAndSettle();
      expect(find.text('profile: $id'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Writer'), findsOneWidget);
      expect(find.text('writer'), findsOneWidget);
      expect(repository.queries, ['unknown', 'writer']);
    },
  );
}
