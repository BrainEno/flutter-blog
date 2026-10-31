import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/widgets/no_wave_action_row.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/pages/login_page.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/data/repositories/comment_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/pages/saved_blogs_page.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/blog/presentation/pages/recycle_bin_page.dart';
import 'package:belog/features/blog/presentation/pages/user_blogs_page.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/models/author_profile_model.dart';
import 'package:belog/features/user/data/repositories/author_repository_impl.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/presentation/pages/author_page.dart';
import 'package:belog/features/user/presentation/pages/profile_page.dart';
import 'package:belog/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockBlogRemote extends Mock implements BlogRemoteDataSource {}

class MockBlogLocal extends Mock implements BlogLocalDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCommentRemote extends Mock implements CommentRemoteDataSource {}

class MockAuthorRemote extends Mock implements AuthorRemoteDataSource {}

class MemoryThemeStore implements ThemePreferenceStore {
  ThemeMode mode = ThemeMode.system;

  @override
  Future<ThemeMode> load() async => mode;

  @override
  Future<void> save(ThemeMode value) async => mode = value;
}

BlogModel sampleBlog(String id, String title) => BlogModel(
  id: id,
  title: title,
  content: '正文',
  posterId: 'author',
  imageUrl: '',
  tags: const ['诗歌'],
  updatedAt: DateTime.utc(2025),
);

User sampleUser() => User(
  id: 'user',
  email: 'user@example.invalid',
  name: '测试用户',
  updatedAt: DateTime.utc(2024),
);

/// Builds the real widget tree with every service replaced by mocks, exactly
/// like [initDependencies] would register them in production.
class Harness {
  final MockBlogRemote remote = MockBlogRemote();
  final MockCommentRemote commentRemote = MockCommentRemote();
  final MockAuthorRemote authorRemote = MockAuthorRemote();
  final MockBlogLocal local = MockBlogLocal();
  final MockConnection connection = MockConnection();
  final MockAuthRepository authRepository = MockAuthRepository();
  late final ThemeBloc themeBloc;
  late final AppUserCubit appUserCubit;
  late final AuthBloc authBloc;
  GoRouter? router;

  Harness() {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(
      () => remote.getAllBlogs(page: 1),
    ).thenAnswer((_) async => <BlogModel>[]);
    when(
      () => remote.getBlogById(any()),
    ).thenAnswer((_) async => sampleBlog('abc', '深链文章'));
    when(
      () => remote.getUserLikedBlogs(any()),
    ).thenAnswer((_) async => <BlogModel>[]);
    when(
      () => remote.getRelatedArticles(any()),
    ).thenAnswer((_) async => <BlogModel>[]);
    when(
      () => commentRemote.getComments(any()),
    ).thenAnswer((_) async => <CommentModel>[]);
    when(() => authorRemote.getAuthorProfile(any())).thenAnswer(
      (_) async => AuthorProfileModel(
        userId: 'author',
        displayName: '深链作者',
        followerCount: 1,
        updatedAt: DateTime.utc(2025),
      ),
    );
    when(
      () => remote.getBlogsByPosterId('author'),
    ).thenAnswer((_) async => <BlogModel>[]);
    when(
      () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
    ).thenAnswer((_) async {});
    when(() => local.loadBlogs()).thenAnswer((_) async => <BlogModel>[]);
    when(() => local.loadBlogById(any())).thenAnswer((_) async => null);
    when(
      () => authRepository.currentUser(),
    ).thenAnswer((_) async => Left(Failure('no session')));
    when(
      () => authRepository.logout(),
    ).thenAnswer((_) async => Right<Failure, void>(null));

    final repository = BlogRepositoryImpl(remote, local, connection);
    final sl = GetIt.instance;
    sl
      ..registerFactory(() => GetAllBlogs(repository))
      ..registerFactory(() => GetBlogById(repository))
      ..registerFactory(() => SearchBlogs(repository))
      ..registerFactory(() => ToggleLikeBlog(repository))
      ..registerFactory(() => IsBlogLiked(repository))
      ..registerFactory(() => GetUserLikedBlogs(repository))
      ..registerFactory(() => UploadBlog(repository))
      ..registerFactory(() => UpdateBlog(repository))
      ..registerFactory(() => DeleteBlog(repository))
      ..registerFactory(() => GetBlogsByPoster(repository))
      ..registerFactory(() => GetRelatedArticles(repository))
      ..registerFactory(() => BlogBloc(getAllBlogs: sl<GetAllBlogs>()))
      ..registerFactory(() => BlogSearchBloc(searchBlogs: sl<SearchBlogs>()))
      ..registerFactory(
        () => BlogLikedBloc(
          toggleBlogLike: sl<ToggleLikeBlog>(),
          isBlogLiked: sl<IsBlogLiked>(),
          getUserLikedBlogs: sl<GetUserLikedBlogs>(),
        ),
      )
      ..registerFactory(
        () => BlogUploadBloc(
          uploadBlog: sl<UploadBlog>(),
          updateBlog: sl<UpdateBlog>(),
          deleteBlog: sl<DeleteBlog>(),
        ),
      )
      ..registerFactory(
        () => BlogByBloc(getBlogsByPoster: sl<GetBlogsByPoster>()),
      );

    final commentRepository = CommentRepositoryImpl(
      commentRemoteDataSource: commentRemote,
      connectionChecker: connection,
    );
    sl
      ..registerFactory(() => GetComments(commentRepository))
      ..registerFactory(() => CreateComment(commentRepository))
      ..registerFactory(() => DeleteComment(commentRepository));

    final authorRepository = AuthorRepositoryImpl(
      authorRemoteDataSource: authorRemote,
      connectionChecker: connection,
    );
    sl
      ..registerFactory(() => GetAuthorProfile(authorRepository))
      ..registerFactory(() => FollowAuthor(authorRepository))
      ..registerFactory(() => UnfollowAuthor(authorRepository));

    themeBloc = ThemeBloc(MemoryThemeStore());
    appUserCubit = AppUserCubit();
    authBloc = AuthBloc(
      userSignUp: UserSignUp(authRepository),
      userLogin: UserLogin(authRepository),
      userSignOut: UserSignOut(authRepository),
      currentUser: CurrentUser(authRepository),
      appUserCubit: appUserCubit,
    );
  }

  GoRouter buildRouter({String initialLocation = '/'}) {
    return router = createAppRouter(
      appUserCubit: appUserCubit,
      initialLocation: initialLocation,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    double textScale = 1,
    bool disableAnimations = false,
  }) async {
    final currentRouter = router;
    assert(currentRouter != null, 'call buildRouter before pump');
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeBloc>.value(value: themeBloc),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<AppUserCubit>.value(value: appUserCubit),
        ],
        child: MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: currentRouter,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    router?.dispose();
    await authBloc.close();
    await appUserCubit.close();
    await themeBloc.close();
    GetIt.instance.reset();
  }
}

void main() {
  setUp(() => GetIt.instance.reset());

  testWidgets('each tab keeps its own stack across tab switches', (
    tester,
  ) async {
    final harness = Harness()..buildRouter();
    when(
      () => harness.remote.getAllBlogs(page: 1),
    ).thenAnswer((_) async => [sampleBlog('1', '第一篇文章')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(BlogPage), findsOneWidget);

    // Open the viewer on top of the feed tab's stack.
    await tester.tap(find.byType(BlogCard));
    await tester.pumpAndSettle();
    expect(find.byType(BlogViewerPage), findsOneWidget);

    // Switch to the search tab and back.
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBlogPage), findsOneWidget);
    expect(find.byType(BlogViewerPage), findsNothing);

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();

    // The feed tab still shows the viewer: its stack survived the switches.
    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(find.byType(BlogPage), findsNothing);

    // Back returns to the feed inside the same tab.
    final backLabel = MaterialLocalizations.of(
      tester.element(find.byType(BlogViewerPage)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backLabel));
    await tester.pumpAndSettle();
    expect(find.byType(BlogPage), findsOneWidget);
  });

  testWidgets('reduced motion removes the tab-switch fade', (tester) async {
    final harness = Harness()..buildRouter();
    addTearDown(harness.dispose);
    await harness.pump(tester, disableAnimations: true);
    await tester.pumpAndSettle();
    final tabFade = find.byWidgetPredicate(
      (widget) =>
          widget is FadeTransition && widget.child is StatefulNavigationShell,
    );
    expect(tabFade, findsNothing);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBlogPage), findsOneWidget);
    expect(tabFade, findsNothing);
  });

  testWidgets('protected tab redirects to login and returns after sign-in', (
    tester,
  ) async {
    final harness = Harness()..buildRouter();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(SavedBlogsPage), findsNothing);

    // Signing in returns the user to the tab they wanted to open.
    harness.appUserCubit.updateUser(sampleUser());
    await tester.pumpAndSettle();
    expect(find.byType(SavedBlogsPage), findsOneWidget);
    expect(find.text('你还没有收藏文章'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('deep link /view/:id loads the article by id', (tester) async {
    final harness = Harness()..buildRouter(initialLocation: '/view/abc');
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(find.text('深链文章'), findsOneWidget);
    verify(() => harness.remote.getBlogById('abc')).called(1);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('viewer metadata and images are accessible at 2x: $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        previousErrorHandler?.call(details);
      };
      try {
        final harness = Harness()..buildRouter(initialLocation: '/view/abc');
        addTearDown(harness.dispose);
        await harness.pump(tester, locale: locale, textScale: 2);
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        expect(find.text(l10n.anonymousAuthor), findsOneWidget);
        expect(find.text(l10n.readingTimeMinutes(1)), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BlogViewerPage),
            matching: find.byTooltip(l10n.saveTooltip),
          ),
          findsOneWidget,
        );
        // The editorial header places the cover below the title and author;
        // at large text sizes it can start outside the viewport.
        await tester.ensureVisible(
          find
              .descendant(
                of: find.byType(BlogViewerPage),
                matching: find.byType(ArticleCover),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp(l10n.coverOf('深链文章'))),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = previousErrorHandler;
        semantics.dispose();
      }
    });
  }

  testWidgets('deep link /author/:userId loads the author page', (
    tester,
  ) async {
    final harness = Harness()..buildRouter(initialLocation: '/author/author');
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(AuthorPage), findsOneWidget);
    expect(find.text('深链作者'), findsOneWidget);
    expect(find.text('还没有发布文章'), findsOneWidget);
    verify(() => harness.authorRemote.getAuthorProfile('author')).called(1);
  });

  testWidgets('reader and author navigation stay on the search tab stack', (
    tester,
  ) async {
    final harness = Harness()..buildRouter(initialLocation: '/search/view/abc');
    addTearDown(harness.dispose);
    when(
      () => harness.remote.getBlogsByPosterId('author'),
    ).thenAnswer((_) async => [sampleBlog('another', '作者的另一篇文章')]);
    await harness.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.text('匿名作者'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthorPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.ensureVisible(find.text('作者的另一篇文章'));
    await tester.tap(find.text('作者的另一篇文章'));
    await tester.pumpAndSettle();
    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(BlogViewerPage), findsOneWidget);
    final backLabel = MaterialLocalizations.of(
      tester.element(find.byType(BlogViewerPage)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backLabel));
    await tester.pumpAndSettle();
    expect(find.byType(AuthorPage), findsOneWidget);
    await tester.tap(find.byTooltip(backLabel));
    await tester.pumpAndSettle();
    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(find.text('深链文章'), findsOneWidget);
  });

  testWidgets('article deletion still requires confirmation', (tester) async {
    final harness = Harness();
    addTearDown(harness.dispose);
    final article = sampleBlog(
      'editable',
      '可删除的文章',
    ).copyWith(articleId: 'article-uuid');
    var deleted = false;
    when(
      () => harness.remote.getBlogsByPosterId('user'),
    ).thenAnswer((_) async => deleted ? <BlogModel>[] : [article]);
    when(
      () => harness.remote.getBlogById('editable'),
    ).thenAnswer((_) async => article);
    when(() => harness.remote.deleteArticle('article-uuid')).thenAnswer((
      _,
    ) async {
      deleted = true;
      return true;
    });
    when(
      () => harness.local.deleteCachedBlog('editable'),
    ).thenAnswer((_) async {});
    harness.appUserCubit.updateUser(sampleUser());
    harness.buildRouter(initialLocation: '/profile/my-articles');
    await harness.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除文章'));
    await tester.pumpAndSettle();
    expect(find.text('确定删除「可删除的文章」吗？删除后可在回收站中恢复。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    verifyNever(() => harness.remote.deleteArticle(any()));
    expect(find.text('可删除的文章'), findsOneWidget);

    await tester.tap(find.byTooltip('删除文章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    verify(() => harness.remote.deleteArticle('article-uuid')).called(1);
    expect(find.text('您还没有发布任何文章'), findsOneWidget);
  });

  testWidgets('profile to recycle bin restores and refreshes my articles', (
    tester,
  ) async {
    final harness = Harness();
    addTearDown(harness.dispose);
    var restored = false;
    when(() => harness.remote.getBlogsByPosterId('user')).thenAnswer(
      (_) async => restored ? [sampleBlog('restored', '恢复的文章')] : <BlogModel>[],
    );
    when(() => harness.remote.getDeletedBlogs()).thenAnswer(
      (_) async => [
        DeletedBlog(
          articleId: 'deleted-uuid',
          title: '恢复的文章',
          imageUrl: '',
          deletedAt: DateTime.utc(2026, 10, 1),
          purgesAt: null,
        ),
      ],
    );
    when(() => harness.remote.restoreArticle('deleted-uuid')).thenAnswer((
      _,
    ) async {
      restored = true;
      return sampleBlog('restored', '恢复的文章');
    });
    final repository = BlogRepositoryImpl(
      harness.remote,
      harness.local,
      harness.connection,
    );
    GetIt.instance.registerFactory(
      () => RecycleBinBloc(
        getDeletedBlogs: GetDeletedBlogs(repository),
        restoreDeletedBlog: RestoreDeletedBlog(repository),
      ),
    );
    harness.appUserCubit.updateUser(sampleUser());
    harness.buildRouter(initialLocation: '/profile');
    await harness.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的文章'));
    await tester.pumpAndSettle();
    expect(find.byType(UserBlogsPage), findsOneWidget);
    expect(find.text('您还没有发布任何文章'), findsOneWidget);
    await tester.tap(find.byTooltip('回收站'));
    await tester.pumpAndSettle();
    expect(find.byType(RecycleBinPage), findsOneWidget);
    expect(find.text('恢复的文章'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    verify(() => harness.remote.restoreArticle('deleted-uuid')).called(1);
    expect(find.text('回收站是空的'), findsOneWidget);

    harness.router!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(UserBlogsPage), findsOneWidget);
    expect(find.text('恢复的文章'), findsOneWidget);
    verify(() => harness.remote.getBlogsByPosterId('user')).called(2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing out from the profile lands on the login page', (
    tester,
  ) async {
    final harness = Harness();
    harness.buildRouter(initialLocation: '/profile');
    harness.appUserCubit.updateUser(sampleUser());
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    // Scroll to the action row before tapping its full ink response.
    final signOutTile = find.widgetWithText(NoWaveActionRow, '退出登录');
    await tester.scrollUntilVisible(
      signOutTile,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(signOutTile);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(ProfilePage), findsNothing);
    verify(() => harness.authRepository.logout()).called(1);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('unknown routes have a localized recovery action: $locale', (
      tester,
    ) async {
      final harness = Harness()..buildRouter(initialLocation: '/missing-page');
      addTearDown(harness.dispose);
      await harness.pump(tester, locale: locale);
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.pageNotFound), findsOneWidget);
      await tester.tap(find.text(l10n.backToHome));
      await tester.pumpAndSettle();
      expect(find.byType(BlogPage), findsOneWidget);
    });
  }

  testWidgets('the editor is not reachable without an account', (tester) async {
    final harness = Harness()..buildRouter();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    harness.router!.go('/editor');
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
