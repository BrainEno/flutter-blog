import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/pages/saved_blogs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements BlogRemoteDataSource {}

class MockLocal extends Mock implements BlogLocalDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  testWidgets('offline list failure can be retried after reconnecting',
      (tester) async {
    var connected = false;
    final connection = MockConnection();
    final remote = MockRemote();
    when(() => connection.isConnected).thenAnswer((_) async => connected);
    when(() => remote.getUserLikedBlogs('user'))
        .thenAnswer((_) async => <BlogModel>[]);
    final repo = BlogRepositoryImpl(remote, MockLocal(), connection);
    final likes = BlogLikedBloc(
      toggleBlogLike: ToggleLikeBlog(repo),
      isBlogLiked: IsBlogLiked(repo),
      getUserLikedBlogs: GetUserLikedBlogs(repo),
    );
    final user = AppUserCubit()
      ..updateUser(User(
        id: 'user',
        email: 'test@example.invalid',
        name: 'Test',
        updatedAt: DateTime.utc(2024),
      ));
    addTearDown(() async {
      await likes.close();
      await user.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BlogLikedBloc>.value(value: likes),
          BlocProvider<AppUserCubit>.value(value: user),
        ],
        child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
home: SavedBlogsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('无法连接到网络'), findsWidgets);
    expect(find.text('重试'), findsOneWidget);
    verifyNever(() => remote.getUserLikedBlogs(any()));

    connected = true;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('你还没有收藏文章'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    verify(() => remote.getUserLikedBlogs('user')).called(1);
  });
}
