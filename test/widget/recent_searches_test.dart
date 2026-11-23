import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/utils/search_debounce.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/recent_search_store.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/blog/presentation/search/recent_searches.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/router/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

class _Store implements RecentSearchStore {
  _Store([Map<String, List<String>>? saved]) : saved = saved ?? {};
  final Map<String, List<String>> saved;

  @override
  Future<List<String>> load({required String userId}) async =>
      saved[userId] ?? const [];

  @override
  Future<void> save({
    required String userId,
    required List<String> queries,
  }) async {
    saved[userId] = queries;
  }
}

class _Search implements SearchBlogs {
  final queries = <String>[];

  @override
  Future<Either<Failure, List<Blog>>> call(SearchBlogsParams params) async {
    queries.add(params.query);
    return right([
      Blog(
        id: 'found',
        title: 'Found for ${params.query}',
        content: 'Body',
        posterId: 'author',
        posterName: '',
        imageUrl: '',
        tags: const [],
        updatedAt: DateTime(2026, 11, 19),
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user(String id) =>
    User(id: id, email: '$id@example.com', name: id, updatedAt: DateTime(2025));

void main() {
  const locale = Locale('zh');
  final l10n = lookupAppLocalizations(locale);

  late _Store store;
  late _Search search;
  late AppUserCubit users;
  late RecentSearches recent;
  late BlogSearchBloc bloc;

  Future<void> pumpPage(WidgetTester tester, {bool signedIn = true}) async {
    users = AppUserCubit();
    if (signedIn) users.updateUser(_user('ann'));
    recent = RecentSearches(store, users: users);
    bloc = BlogSearchBloc(searchBlogs: search);
    addTearDown(() async {
      await bloc.close();
      await users.close();
    });
    final router = GoRouter(
      initialLocation: RoutePaths.search,
      routes: [
        GoRoute(
          path: RoutePaths.search,
          builder: (_, _) => SearchBlogPage(recentSearches: recent),
          routes: [
            GoRoute(
              path: 'view/:id',
              builder: (_, _) => const Scaffold(body: Text('opened')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      BlocProvider<BlogSearchBloc>.value(
        value: bloc,
        child: MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en')],
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  setUp(() {
    store = _Store({
      'ann': ['巡逻队', 'wall'],
    });
    search = _Search();
  });

  testWidgets('the empty field offers the recent searches', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpPage(tester);
      expect(find.text(l10n.recentSearchesTitle), findsOneWidget);
      expect(find.text('巡逻队'), findsOneWidget);
      expect(find.text('wall'), findsOneWidget);
      expect(find.text(l10n.searchInitial), findsNothing);
      expect(
        find.bySemanticsLabel(l10n.recentSearchAgain('wall')),
        findsOneWidget,
      );
      expect(find.byTooltip(l10n.recentSearchRemove('wall')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tapping one searches again and moves it to the top', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text('wall'));
    await tester.pumpAndSettle();
    expect(search.queries, ['wall']);
    expect(field(tester).controller!.text, 'wall');
    expect(find.text('Found for wall'), findsOneWidget);
    expect(recent.queries, ['wall', '巡逻队']);
    // The typed text changed, but no second search goes out after the
    // debounce: the tap already sent it.
    await tester.pump(kSearchDebounceDelay * 2);
    expect(search.queries, ['wall']);

    // Emptying the field brings the list back, newest first.
    await tester.tap(find.byTooltip(l10n.clearSearch));
    await tester.pumpAndSettle();
    final titles = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('recent-searches')),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .toList();
    expect(titles.indexOf('wall'), lessThan(titles.indexOf('巡逻队')));
  });

  testWidgets('the cross removes one; the last one brings the prompt back', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip(l10n.recentSearchRemove('wall')));
    await tester.pumpAndSettle();
    expect(find.text('wall'), findsNothing);
    expect(find.text('巡逻队'), findsOneWidget);
    expect(store.saved['ann'], ['巡逻队']);

    await tester.tap(find.byTooltip(l10n.recentSearchRemove('巡逻队')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.recentSearchesTitle), findsNothing);
    expect(find.text(l10n.searchInitial), findsOneWidget);
    expect(search.queries, isEmpty);
  });

  testWidgets('clear empties the list, and undo brings it back', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text(l10n.actionClear));
    await tester.pumpAndSettle();
    expect(find.text('巡逻队'), findsNothing);
    expect(find.text(l10n.searchInitial), findsOneWidget);
    expect(find.text(l10n.recentSearchesCleared), findsOneWidget);
    expect(store.saved['ann'], isEmpty);

    await tester.tap(find.text(l10n.actionUndo));
    await tester.pumpAndSettle();
    expect(find.text('巡逻队'), findsOneWidget);
    expect(find.text('wall'), findsOneWidget);
    expect(store.saved['ann'], ['巡逻队', 'wall']);
  });

  testWidgets('pressing search keeps the query; typing alone does not', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField), 'ra');
    await tester.pump(kSearchDebounceDelay);
    await tester.pumpAndSettle();
    expect(search.queries, ['ra']);
    expect(recent.queries, ['巡逻队', 'wall']);

    await tester.enterText(find.byType(TextField), ' rain ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.queries.last, 'rain');
    expect(recent.queries, ['rain', '巡逻队', 'wall']);
  });

  testWidgets('opening a result keeps the query that found it', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField), 'harbour');
    await tester.pump(kSearchDebounceDelay);
    await tester.pumpAndSettle();
    expect(recent.queries, ['巡逻队', 'wall']);

    await tester.tap(find.text('Found for harbour'));
    await tester.pumpAndSettle();
    expect(find.text('opened'), findsOneWidget);
    expect(recent.queries, ['harbour', '巡逻队', 'wall']);
  });

  testWidgets('a guest sees the prompt and leaves nothing behind', (
    tester,
  ) async {
    await pumpPage(tester, signedIn: false);
    expect(find.text(l10n.recentSearchesTitle), findsNothing);
    expect(find.text(l10n.searchInitial), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.queries, ['secret']);
    expect(recent.queries, isEmpty);
    expect(store.saved.keys, ['ann']);
  });
}
