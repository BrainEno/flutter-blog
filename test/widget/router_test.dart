import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
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
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
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
import 'package:belog/features/blog/presentation/blocs/bog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/pages/saved_blogs_page.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
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
  final MockBlogLocal local = MockBlogLocal();
  final MockConnection connection = MockConnection();
  final MockAuthRepository authRepository = MockAuthRepository();
  late final ThemeBloc themeBloc;
  late final AppUserCubit appUserCubit;
  late final AuthBloc authBloc;
  GoRouter? router;

  Harness() {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.getAllBlogs(page: 1))
        .thenAnswer((_) async => <BlogModel>[]);
    when(() => remote.getBlogById(any()))
        .thenAnswer((_) async => sampleBlog('abc', '深链文章'));
    when(() => remote.getUserLikedBlogs(any()))
        .thenAnswer((_) async => <BlogModel>[]);
    when(() => local.uploadLocalBlogs(blogs: any(named: 'blogs')))
        .thenAnswer((_) async {});
    when(() => local.loadBlogs()).thenAnswer((_) async => <BlogModel>[]);
    when(() => local.loadBlogById(any())).thenAnswer((_) async => null);
    when(() => authRepository.currentUser())
        .thenAnswer((_) async => Left(Failure('no session')));
    when(() => authRepository.logout())
        .thenAnswer((_) async => Right<Failure, void>(null));

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

  Future<void> pump(WidgetTester tester) async {
    final currentRouter = router;
    assert(currentRouter != null, 'call buildRouter before pump');
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeBloc>.value(value: themeBloc),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<AppUserCubit>.value(value: appUserCubit),
        ],
        child: MaterialApp.router(routerConfig: currentRouter),
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
    when(() => harness.remote.getAllBlogs(page: 1))
        .thenAnswer((_) async => [sampleBlog('1', '第一篇文章')]);
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BlogPage), findsOneWidget);
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

  testWidgets('signing out from the profile lands on the login page', (
    tester,
  ) async {
    final harness = Harness();
    harness.buildRouter(initialLocation: '/profile');
    harness.appUserCubit.updateUser(sampleUser());
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    // The profile list lost an entry in the no-wave migration (G2 hides
    // account settings), which moved the sign-out tile to a screen position
    // where tapping the Text widget itself lands outside its render box.
    // Tap the ListTile instead: its whole area belongs to the ink response.
    final signOutTile = find.widgetWithText(ListTile, '退出登录');
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
