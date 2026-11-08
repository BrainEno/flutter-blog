import 'dart:async';

import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/author_articles_paging.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_author_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/user/presentation/pages/author_page.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockGetAuthorProfile extends Mock implements GetAuthorProfile {}

class MockFollowAuthor extends Mock implements FollowAuthor {}

class MockUnfollowAuthor extends Mock implements UnfollowAuthor {}

class MockBlogRepository extends Mock implements BlogRepository {}

AuthorProfile _profile({bool isFollowing = false}) => AuthorProfile(
  userId: 'author-1',
  displayName: '作者甲',
  bio: '写点东西',
  websiteUrl: 'https://example.invalid',
  followerCount: 12,
  followingCount: 3,
  isFollowing: isFollowing,
  updatedAt: DateTime.utc(2025),
);

BlogModel _blog() => BlogModel(
  id: 'post-1',
  title: '作者的文章',
  content: '正文',
  posterId: 'author-1',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2025),
);

User _user() => User(
  id: 'viewer-1',
  email: 'viewer@example.invalid',
  name: '读者',
  updatedAt: DateTime.utc(2024),
);

/// Pumps the page behind a minimal router so the login redirect has a
/// real destination.
Future<void> _pumpPage(
  WidgetTester tester, {
  required AppUserCubit appUserCubit,
  required AuthorCubit authorCubit,
  required BlogByBloc blogByBloc,
  Locale locale = const Locale('zh'),
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => MultiBlocProvider(
          providers: [
            BlocProvider<AppUserCubit>.value(value: appUserCubit),
            BlocProvider<AuthorCubit>.value(value: authorCubit),
            BlocProvider<BlogByBloc>.value(value: blogByBloc),
          ],
          child: const AuthorPage(userId: 'author-1'),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('登录页'),
              Text('redirect: ${state.uri.queryParameters['redirect']}'),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/view/:id',
        builder: (context, state) => Scaffold(
          appBar: AppBar(),
          body: Text('article: ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return tester.pumpWidget(
    MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightThemeMode,
      darkTheme: AppTheme.darkThemeMode,
      themeMode: themeMode,
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
  late MockGetAuthorProfile getAuthorProfile;
  late MockFollowAuthor followAuthor;
  late MockUnfollowAuthor unfollowAuthor;
  late MockBlogRepository blogRepository;
  late AppUserCubit appUserCubit;

  setUp(() {
    registerFallbackValue(BlogFeedKind.latest);
    getAuthorProfile = MockGetAuthorProfile();
    followAuthor = MockFollowAuthor();
    unfollowAuthor = MockUnfollowAuthor();
    blogRepository = MockBlogRepository();
    appUserCubit = AppUserCubit();

    when(
      () => getAuthorProfile('author-1'),
    ).thenAnswer((_) async => right<Failure, AuthorProfile>(_profile()));
    // The author page browses one page at a time; the data export is the only
    // caller of the one-shot read, and it is not exercised here.
    when(
      () => blogRepository.getAuthorArticlePage(
        'author-1',
        kind: any(named: 'kind'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => right<Failure, List<Blog>>([_blog()]));
  });

  tearDown(() => appUserCubit.close());

  /// Blocs are built inside each test body: their event queues are
  /// zone-bound, so building them in setUp (outside the fake-async zone)
  /// would never deliver events.
  AuthorCubit buildAuthorCubit() => AuthorCubit(
    getAuthorProfile: getAuthorProfile,
    followAuthor: followAuthor,
    unfollowAuthor: unfollowAuthor,
    userId: 'author-1',
  );

  BlogByBloc buildBlogByBloc() => BlogByBloc(
    getAuthorArticles: GetAuthorArticles(blogRepository),
    getMyArticles: GetMyArticles(blogRepository),
    getMyArticleEditions: GetMyArticleEditions(blogRepository),
  );

  testWidgets('renders the profile and the article list', (tester) async {
    appUserCubit.updateUser(_user());
    final authorCubit = buildAuthorCubit();
    addTearDown(authorCubit.close);
    final blogByBloc = buildBlogByBloc();
    addTearDown(blogByBloc.close);

    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    expect(find.text('作者甲'), findsOneWidget);
    expect(find.text('写点东西'), findsOneWidget);
    expect(find.text('粉丝 12 · 关注 3'), findsOneWidget);
    expect(find.byType(NoWaveAvatar), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'https://example.invalid'),
      findsOneWidget,
    );
    expect(find.text('作者的文章'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('English author page localizes counts, empty and follow errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      appUserCubit.updateUser(_user());
      when(() => getAuthorProfile('author-1')).thenAnswer(
        (_) async => right<Failure, AuthorProfile>(
          AuthorProfile(
            userId: 'author-1',
            displayName: '',
            followerCount: 1234,
            followingCount: 5,
            updatedAt: DateTime.utc(2025),
          ),
        ),
      );
      when(
        () => blogRepository.getAuthorArticlePage(
          'author-1',
          kind: any(named: 'kind'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => right<Failure, List<Blog>>(const []));
      when(() => followAuthor('author-1')).thenAnswer(
        (_) async => left<Failure, AuthorProfile>(Failure.networkOffline()),
      );
      final authorCubit = buildAuthorCubit();
      final blogByBloc = buildBlogByBloc();
      addTearDown(authorCubit.close);
      addTearDown(blogByBloc.close);

      await _pumpPage(
        tester,
        appUserCubit: appUserCubit,
        authorCubit: authorCubit,
        blogByBloc: blogByBloc,
        locale: const Locale('en'),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Anonymous author'), findsOneWidget);
      expect(find.text('1,234 followers · 5 following'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Avatar of Anonymous author')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('No articles yet'), 140);
      expect(find.text('No articles yet'), findsOneWidget);

      await tester.ensureVisible(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Follow').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(
        find.text('No network connection — check your settings'),
        findsOneWidget,
      );
      expect(find.text('Follow'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('following takes the server answer and flips the button', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    when(() => followAuthor('author-1')).thenAnswer(
      (_) async => right<Failure, AuthorProfile>(_profile(isFollowing: true)),
    );
    final authorCubit = buildAuthorCubit();
    addTearDown(authorCubit.close);
    final blogByBloc = buildBlogByBloc();
    addTearDown(blogByBloc.close);

    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    verify(() => followAuthor('author-1')).called(1);
    expect(find.text('已关注'), findsOneWidget);
    expect(find.text('关注'), findsNothing);
  });

  testWidgets('a failed toggle keeps the server state and reports it', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    when(
      () => followAuthor('author-1'),
    ).thenAnswer((_) async => left<Failure, AuthorProfile>(Failure('网络超时')));
    final authorCubit = buildAuthorCubit();
    addTearDown(authorCubit.close);
    final blogByBloc = buildBlogByBloc();
    addTearDown(blogByBloc.close);

    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(find.text('网络超时'), findsOneWidget);
    // Still the server-resolved state: the button offers to follow.
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('a signed-out visitor is routed to login, not a fake state', (
    tester,
  ) async {
    final authorCubit = buildAuthorCubit();
    addTearDown(authorCubit.close);
    final blogByBloc = buildBlogByBloc();
    addTearDown(blogByBloc.close);

    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(find.text('请先登录账户'), findsOneWidget);
    expect(find.text('登录页'), findsOneWidget);
    expect(find.text('redirect: /'), findsOneWidget);
    verifyNever(() => followAuthor(any()));
  });

  testWidgets('the author themself gets no follow button', (tester) async {
    appUserCubit.updateUser(
      User(
        id: 'author-1',
        email: 'author@example.invalid',
        name: '作者甲',
        updatedAt: DateTime.utc(2024),
      ),
    );
    final authorCubit = buildAuthorCubit();
    addTearDown(authorCubit.close);
    final blogByBloc = buildBlogByBloc();
    addTearDown(blogByBloc.close);

    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    expect(find.text('这是你'), findsOneWidget);
    expect(find.text('关注'), findsNothing);
    expect(find.text('已关注'), findsNothing);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('author page supports large text: $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final profile = AuthorProfile(
            userId: 'author-1',
            displayName: 'A long author name with several words',
            bio: 'A real biography that can wrap in the available space.',
            avatarUrl: 'file:///not-a-network-image',
            websiteUrl: 'https://example.invalid/a-long-author-link',
            followerCount: 1234,
            followingCount: 56,
            updatedAt: DateTime.utc(2025),
          );
          when(
            () => getAuthorProfile('author-1'),
          ).thenAnswer((_) async => right<Failure, AuthorProfile>(profile));
          appUserCubit.updateUser(_user());
          final authorCubit = buildAuthorCubit();
          final blogByBloc = buildBlogByBloc();
          addTearDown(authorCubit.close);
          addTearDown(blogByBloc.close);
          await _pumpPage(
            tester,
            appUserCubit: appUserCubit,
            authorCubit: authorCubit,
            blogByBloc: blogByBloc,
            locale: locale,
            textScale: 2,
            themeMode: mode,
          );
          await tester.pumpAndSettle();
          expect(find.text(profile.displayName), findsOneWidget);
          expect(find.text(profile.bio), findsOneWidget);
          expect(find.byType(NoWaveAvatar), findsOneWidget);
          expect(find.byIcon(Icons.person_outline), findsOneWidget);
          expect(
            find.bySemanticsLabel(
              lookupAppLocalizations(locale).avatarOf(profile.displayName),
            ),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(find.text('作者的文章'), 140);
          expect(find.text('作者的文章'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('author articles open and return to the author page', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    final authorCubit = buildAuthorCubit();
    final blogByBloc = buildBlogByBloc();
    addTearDown(authorCubit.close);
    addTearDown(blogByBloc.close);
    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('作者的文章'));
    await tester.tap(find.text('作者的文章'));
    await tester.pumpAndSettle();
    expect(find.text('article: post-1'), findsOneWidget);
    final backLabel = MaterialLocalizations.of(
      tester.element(find.text('article: post-1')),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backLabel));
    await tester.pumpAndSettle();
    expect(find.byType(AuthorPage), findsOneWidget);
    expect(find.text('作者甲'), findsOneWidget);
  });

  testWidgets(
    'follow is guarded in flight and unfollow uses the server result',
    (tester) async {
      appUserCubit.updateUser(_user());
      final pending = Completer<Either<Failure, AuthorProfile>>();
      when(() => followAuthor('author-1')).thenAnswer((_) => pending.future);
      when(
        () => unfollowAuthor('author-1'),
      ).thenAnswer((_) async => right<Failure, AuthorProfile>(_profile()));
      final authorCubit = buildAuthorCubit();
      final blogByBloc = buildBlogByBloc();
      addTearDown(authorCubit.close);
      addTearDown(blogByBloc.close);
      await _pumpPage(
        tester,
        appUserCubit: appUserCubit,
        authorCubit: authorCubit,
        blogByBloc: blogByBloc,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('关注'));
      await tester.pump();
      final follow = tester.widget<NoWaveButton>(
        find.widgetWithText(NoWaveButton, '关注'),
      );
      expect(follow.onPressed, isNull);
      await tester.tap(find.text('关注'), warnIfMissed: false);
      await tester.pump();
      verify(() => followAuthor('author-1')).called(1);
      pending.complete(right(_profile(isFollowing: true)));
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsOneWidget);
      await tester.tap(find.text('已关注'));
      await tester.pumpAndSettle();
      verify(() => unfollowAuthor('author-1')).called(1);
      expect(find.text('关注'), findsOneWidget);
    },
  );

  testWidgets('profile and article failures can be retried independently', (
    tester,
  ) async {
    var profileRequests = 0;
    var articleRequests = 0;
    when(() => getAuthorProfile('author-1')).thenAnswer((_) async {
      profileRequests++;
      return profileRequests == 1
          ? left<Failure, AuthorProfile>(Failure.networkOffline())
          : right<Failure, AuthorProfile>(_profile());
    });
    when(
      () => blogRepository.getAuthorArticlePage(
        'author-1',
        kind: any(named: 'kind'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async {
      articleRequests++;
      return articleRequests == 1
          ? left<Failure, List<Blog>>(Failure.networkOffline())
          : right<Failure, List<Blog>>([_blog()]);
    });
    final authorCubit = buildAuthorCubit();
    final blogByBloc = buildBlogByBloc();
    addTearDown(authorCubit.close);
    addTearDown(blogByBloc.close);
    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No network connection — check your settings'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('作者甲'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('作者的文章'), findsOneWidget);
    expect(profileRequests, 2);
    expect(articleRequests, 2);
  });

  testWidgets('the list offers both orders and pages past the first', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    final calls = <(BlogFeedKind, int)>[];
    when(
      () => blogRepository.getAuthorArticlePage(
        'author-1',
        kind: any(named: 'kind'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((invocation) async {
      final kind = invocation.namedArguments[#kind] as BlogFeedKind;
      final offset = invocation.namedArguments[#offset] as int;
      calls.add((kind, offset));
      return right<Failure, List<Blog>>([
        for (var i = 0; i < kAuthorPageSize; i++)
          _blog().copyWith(id: 'a${offset + i}'),
      ]);
    });
    final authorCubit = buildAuthorCubit();
    final blogByBloc = buildBlogByBloc();
    addTearDown(authorCubit.close);
    addTearDown(blogByBloc.close);
    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    expect(calls.single, (BlogFeedKind.latest, 0));

    // The first full page is not the end of the list.
    await tester.ensureVisible(find.text('加载更多作品'));
    await tester.tap(find.text('加载更多作品'));
    await tester.pumpAndSettle();
    expect(calls.last, (BlogFeedKind.latest, kAuthorPageSize));

    await tester.ensureVisible(find.text('最多收藏'));
    await tester.tap(find.text('最多收藏'));
    await tester.pumpAndSettle();
    expect(calls.last, (BlogFeedKind.popular, 0));
  });

  testWidgets('a refused deeper most-saved page offers the way out', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    when(
      () => blogRepository.getAuthorArticlePage(
        'author-1',
        kind: any(named: 'kind'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((invocation) async {
      final kind = invocation.namedArguments[#kind] as BlogFeedKind;
      final offset = invocation.namedArguments[#offset] as int;
      if (kind == BlogFeedKind.popular && offset > 0) {
        // What the server answers past its bound: not a network problem, and
        // not retryable.
        return left<Failure, List<Blog>>(
          const Failure(
            'offset is limited',
            kind: FailureKind.validation,
            code: 'server.BAD_USER_INPUT',
          ),
        );
      }
      return right<Failure, List<Blog>>([
        for (var i = 0; i < kAuthorPageSize; i++)
          _blog().copyWith(id: '${kind.name}$offset$i'),
      ]);
    });
    final authorCubit = buildAuthorCubit();
    final blogByBloc = buildBlogByBloc();
    addTearDown(authorCubit.close);
    addTearDown(blogByBloc.close);
    await _pumpPage(
      tester,
      appUserCubit: appUserCubit,
      authorCubit: authorCubit,
      blogByBloc: blogByBloc,
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('最多收藏'));
    await tester.tap(find.text('最多收藏'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('加载更多作品'));
    await tester.tap(find.text('加载更多作品'));
    await tester.pumpAndSettle();

    final failed = blogByBloc.state as GetBlogsByUserSuccess;
    expect(failed.depthLimited, isTrue);
    // The rows stay, and the footer explains the bound instead of a retry.
    expect(failed.blogs, hasLength(kAuthorPageSize));
    expect(failed.loadMoreFailure, isNull);
    expect(find.text('去「最新」继续'), findsOneWidget);

    await tester.tap(find.text('去「最新」继续'));
    await tester.pumpAndSettle();
    expect(
      (blogByBloc.state as GetBlogsByUserSuccess).kind,
      BlogFeedKind.latest,
    );
  });
}
