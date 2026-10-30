import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

class _GetArticles implements GetAllBlogs {
  _GetArticles(this.handler);
  final Future<Either<Failure, List<Blog>>> Function(int page) handler;

  @override
  Future<Either<Failure, List<Blog>>> call(GetAllBlogsParams params) =>
      handler(params.page);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchArticles implements SearchBlogs {
  _SearchArticles(this.handler);
  final Future<Either<Failure, List<Blog>>> Function(String query) handler;

  @override
  Future<Either<Failure, List<Blog>>> call(SearchBlogsParams params) =>
      handler(params.query);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Blog _article() => Blog(
  id: 'sample',
  title: 'Sample',
  content: 'The article body',
  posterId: 'author',
  posterName: '',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime(2026, 10, 30),
);

Widget _app({required Locale locale, required Widget child}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: child,
);

void main() {
  for (final language in ['zh', 'en']) {
    final locale = Locale(language);
    final l10n = lookupAppLocalizations(locale);

    testWidgets('$language feed distinguishes loading, error, empty and end', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      final first = Completer<Either<Failure, List<Blog>>>();
      var calls = 0;
      final bloc = BlogBloc(
        getAllBlogs: _GetArticles((_) {
          calls++;
          if (calls == 1) return first.future;
          if (calls == 2) return Future.value(right(const []));
          return Future.value(right([_article()]));
        }),
      );
      final user = AppUserCubit();
      addTearDown(bloc.close);
      addTearDown(user.close);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<BlogBloc>.value(value: bloc),
            BlocProvider<AppUserCubit>.value(value: user),
          ],
          child: _app(locale: locale, child: const BlogPage()),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel(l10n.loadingArticles), findsOneWidget);

      first.complete(left(Failure.networkOffline()));
      await tester.pumpAndSettle();
      expect(find.text(l10n.errorNetworkOffline), findsWidgets);
      expect(find.text(l10n.actionRetry), findsOneWidget);
      expect(find.text(l10n.feedEmpty), findsNothing);

      await tester.tap(find.text(l10n.actionRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.feedEmpty), findsOneWidget);
      expect(find.text(l10n.feedNoMore), findsNothing);

      bloc.add(const BlogFetchFirstPage());
      await tester.pumpAndSettle();
      expect(find.text(l10n.feedNoMore), findsOneWidget);
      expect(find.text(l10n.anonymousAuthor), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(l10n.coverOf('Sample'))), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$language search distinguishes loading, error and no results', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      final first = Completer<Either<Failure, List<Blog>>>();
      var calls = 0;
      final bloc = BlogSearchBloc(
        searchBlogs: _SearchArticles((_) {
          calls++;
          if (calls == 1) return first.future;
          if (calls == 2) return Future.value(right(const []));
          return Future.value(right([_article()]));
        }),
      );
      addTearDown(bloc.close);
      await tester.pumpWidget(
        BlocProvider<BlogSearchBloc>.value(
          value: bloc,
          child: _app(locale: locale, child: const SearchBlogPage()),
        ),
      );
      expect(find.text(l10n.searchInitial), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'search term');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.bySemanticsLabel(l10n.searching), findsOneWidget);

      first.complete(left(Failure.networkOffline()));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.searchFailed(l10n.errorNetworkOffline)),
        findsWidgets,
      );
      expect(find.text(l10n.actionRetry), findsOneWidget);
      await tester.tap(find.text(l10n.actionRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.searchNoResults), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsNothing);
      expect(find.byTooltip(l10n.clearSearch), findsOneWidget);
      bloc.add(const SearchBlogsEvent(query: 'another query'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.searchNoMore), findsOneWidget);
      expect(find.text(l10n.posterLabel(l10n.anonymousAuthor)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system locale changes rebuild existing screen; unsupported falls back to Chinese', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final bloc = BlogSearchBloc(
      searchBlogs: _SearchArticles((_) async => right(const [])),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<BlogSearchBloc>.value(
        value: bloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: const SearchBlogPage(),
        ),
      ),
    );
    expect(find.text('输入关键词，搜索你感兴趣的文章'), findsOneWidget);

    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    await tester.pumpAndSettle();
    expect(find.text('Type a keyword to find articles you like'), findsOneWidget);

    tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
    await tester.pumpAndSettle();
    expect(find.text('输入关键词，搜索你感兴趣的文章'), findsOneWidget);
  });

  testWidgets('large text and keyboard access work on an article card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: ListView(children: [BlogCard(blog: _article())]),
          ),
        ),
        GoRoute(
          path: '/view/:id',
          builder: (context, state) => const Scaffold(body: Text('Opened')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Cover of Sample')), findsWidgets);
    expect(find.text('Anonymous author'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Opened'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
