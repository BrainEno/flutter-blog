import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/user/presentation/pages/author_page.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
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

Blog _blog() => BlogModel(
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
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('登录页'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  return tester.pumpWidget(
    MaterialApp.router(
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
  );
}

void main() {
  late MockGetAuthorProfile getAuthorProfile;
  late MockFollowAuthor followAuthor;
  late MockUnfollowAuthor unfollowAuthor;
  late MockBlogRepository blogRepository;
  late AppUserCubit appUserCubit;

  setUp(() {
    getAuthorProfile = MockGetAuthorProfile();
    followAuthor = MockFollowAuthor();
    unfollowAuthor = MockUnfollowAuthor();
    blogRepository = MockBlogRepository();
    appUserCubit = AppUserCubit();

    when(
      () => getAuthorProfile('author-1'),
    ).thenAnswer((_) async => right<Failure, AuthorProfile>(_profile()));
    when(
      () => blogRepository.getBlogsByUser('author-1'),
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

  BlogByBloc buildBlogByBloc() =>
      BlogByBloc(getBlogsByPoster: GetBlogsByPoster(blogRepository));

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
        () => blogRepository.getBlogsByUser('author-1'),
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

      await tester.scrollUntilVisible(find.text('Follow'), -140);
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
}
