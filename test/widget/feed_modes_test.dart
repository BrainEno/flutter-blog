import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import '../support/locale_test_support.dart';

class _GetFeed implements GetAllBlogs {
  _GetFeed(this.handler);

  final Future<Either<Failure, BlogFeedPage>> Function(GetAllBlogsParams)
  handler;

  @override
  Future<Either<Failure, BlogFeedPage>> call(GetAllBlogsParams params) =>
      handler(params);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Blog _blog(String id) => Blog(
  id: id,
  title: 'Article $id',
  content: 'Body',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: 'Reader',
  updatedAt: DateTime.utc(2026),
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required BlogBloc feed,
  required AppUserCubit user,
  required Locale locale,
  double textScale = 1,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const BlogPage()),
      GoRoute(
        path: '/login',
        builder: (_, state) => Scaffold(
          body: Text(
            'Login redirect: ${state.uri.queryParameters['redirect']}',
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<BlogBloc>.value(value: feed),
        BlocProvider<AppUserCubit>.value(value: user),
        BlocProvider<LocaleBloc>(create: (_) => systemLocaleBloc()),
      ],
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      '${locale.languageCode} switches feeds and clears on sign-out',
      (tester) async {
        final l10n = lookupAppLocalizations(locale);
        final requests = <GetAllBlogsParams>[];
        final user = AppUserCubit()..updateUser(_user('viewer-A'));
        final feed = BlogBloc(
          getAllBlogs: _GetFeed((params) async {
            requests.add(params);
            return Right(
              BlogFeedPage(
                blogs: [_blog(params.kind.name)],
                source: BlogFeedSource.network,
              ),
            );
          }),
        );
        addTearDown(feed.close);
        addTearDown(user.close);
        await _pumpPage(tester, feed: feed, user: user, locale: locale);
        await tester.pumpAndSettle();
        expect(find.text('Article latest'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedTabFeatured));
        await tester.pumpAndSettle();
        expect(find.text('Article featured'), findsOneWidget);
        expect(requests.last.kind, BlogFeedKind.featured);

        await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedTabPopular));
        await tester.pumpAndSettle();
        expect(find.text('Article popular'), findsOneWidget);
        expect(find.text(l10n.feedPopularDescription), findsOneWidget);
        expect(requests.last.kind, BlogFeedKind.popular);

        await tester.tap(
          find.widgetWithText(ChoiceChip, l10n.feedTabFollowing),
        );
        await tester.pumpAndSettle();
        expect(find.text('Article following'), findsOneWidget);
        expect(requests.last.kind, BlogFeedKind.following);
        expect(requests.last.expectedViewerId, 'viewer-A');

        user.updateUser(null);
        // Deliver the cubit's asynchronous stream notification before the
        // next frame, as it is delivered in the real event loop.
        await tester.idle();
        await tester.pump();
        expect(find.text('Article following'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('Article latest'), findsOneWidget);
        expect((feed.state as BlogLoaded).kind, BlogFeedKind.latest);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('${locale.languageCode} shows distinct empty states at 2x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        final l10n = lookupAppLocalizations(locale);
        final user = AppUserCubit()..updateUser(_user('viewer-A'));
        final feed = BlogBloc(
          getAllBlogs: _GetFeed(
            (_) async => const Right(
              BlogFeedPage(blogs: [], source: BlogFeedSource.network),
            ),
          ),
        );
        addTearDown(feed.close);
        addTearDown(user.close);
        await _pumpPage(
          tester,
          feed: feed,
          user: user,
          locale: locale,
          textScale: 2,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedTabFeatured));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.text(l10n.feedFeaturedEmpty), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedTabPopular));
        await tester.pumpAndSettle();
        // At 2x text the status can be below the initial viewport.
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.text(l10n.feedPopularEmpty), findsOneWidget);
        await tester.tap(
          find.widgetWithText(ChoiceChip, l10n.feedTabFollowing),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.text(l10n.feedFollowingEmpty), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('reattaching with a different viewer clears the old feed', (
    tester,
  ) async {
    final requests = <GetAllBlogsParams>[];
    final feed = BlogBloc(
      getAllBlogs: _GetFeed((params) async {
        requests.add(params);
        return Right(
          BlogFeedPage(
            blogs: [_blog(params.kind.name)],
            source: BlogFeedSource.network,
          ),
        );
      }),
    );
    feed.add(
      const BlogFetchFirstPage(
        kind: BlogFeedKind.following,
        viewerId: 'viewer-A',
      ),
    );
    await tester.pump();
    expect(feed.state, isA<BlogLoaded>());
    final user = AppUserCubit()..updateUser(_user('viewer-B'));
    addTearDown(feed.close);
    addTearDown(user.close);

    await _pumpPage(tester, feed: feed, user: user, locale: const Locale('en'));
    expect(find.text('Article following'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Article latest'), findsOneWidget);
    expect((feed.state as BlogLoaded).kind, BlogFeedKind.latest);
    expect(requests.last.kind, BlogFeedKind.latest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out following leads to login without a feed request', (
    tester,
  ) async {
    final requests = <GetAllBlogsParams>[];
    final user = AppUserCubit();
    final feed = BlogBloc(
      getAllBlogs: _GetFeed((params) async {
        requests.add(params);
        return const Right(
          BlogFeedPage(blogs: [], source: BlogFeedSource.network),
        );
      }),
    );
    addTearDown(feed.close);
    addTearDown(user.close);
    await _pumpPage(tester, feed: feed, user: user, locale: const Locale('en'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Following'));
    await tester.pumpAndSettle();

    expect(find.text('Login redirect: /'), findsOneWidget);
    expect(
      requests.every((request) => request.kind == BlogFeedKind.latest),
      isTrue,
    );
  });
}
