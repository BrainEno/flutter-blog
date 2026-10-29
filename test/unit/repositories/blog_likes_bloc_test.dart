import 'dart:async';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements BlogRemoteDataSource {}

class MockLocal extends Mock implements BlogLocalDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  test(
    'offline toggle rolls back optimistic state and reports failure',
    () async {
      final connection = MockConnection();
      final remote = MockRemote();
      when(() => connection.isConnected).thenAnswer((_) async => false);
      final repo = BlogRepositoryImpl(remote, MockLocal(), connection);
      final bloc = BlogLikedBloc(
        toggleBlogLike: ToggleLikeBlog(repo),
        isBlogLiked: IsBlogLiked(repo),
        getUserLikedBlogs: GetUserLikedBlogs(repo),
      );
      addTearDown(bloc.close);

      final states = <BlogLikedState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);
      bloc.add(ToggleBlogLike(userId: 'user', blogId: 'blog'));
      await bloc.stream.firstWhere((state) => state is ToggleBlogLikeFailure);

      // Optimistic success, rolled-back success, then the failure.
      expect(states.first, isA<ToggleBlogLikeSuccess>());
      expect(states.first.likedBlogs['blog'], isTrue);
      final failure = states.whereType<ToggleBlogLikeFailure>().single;
      expect(failure.likedBlogs['blog'], isFalse);
      expect(failure.error, contains('收藏未同步'));
      verifyNever(() => remote.toggleLikeBlog(any(), any()));
    },
  );

  test('rapid double tap sends exactly two requests and lands on the '
      'server truth', () async {
    final connection = MockConnection();
    final remote = MockRemote();
    when(() => connection.isConnected).thenAnswer((_) async => true);

    // Hand-controlled responses so the second tap really arrives while the
    // first request is still in flight.
    final pending = <Completer<bool>>[];
    when(() => remote.toggleLikeBlog('user', 'blog')).thenAnswer((_) {
      final completer = Completer<bool>();
      pending.add(completer);
      return completer.future;
    });
    when(() => remote.getUserLikedBlogs('user'))
        .thenAnswer((_) async => <BlogModel>[]);

    final repo = BlogRepositoryImpl(remote, MockLocal(), connection);
    final bloc = BlogLikedBloc(
      toggleBlogLike: ToggleLikeBlog(repo),
      isBlogLiked: IsBlogLiked(repo),
      getUserLikedBlogs: GetUserLikedBlogs(repo),
    );
    addTearDown(bloc.close);

    final states = <BlogLikedState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    bloc.add(ToggleBlogLike(userId: 'user', blogId: 'blog'));
    await Future<void>.delayed(Duration.zero);
    bloc.add(ToggleBlogLike(userId: 'user', blogId: 'blog'));
    await Future<void>.delayed(Duration.zero);

    expect(
      pending,
      hasLength(1),
      reason: 'second tap is queued while the first is in flight',
    );

    pending[0].complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(
      pending,
      hasLength(2),
      reason: 'queued tap runs after the first response lands',
    );

    pending[1].complete(false);
    await bloc.stream.firstWhere((state) => state is UserLikedBlogsSuccess);

    // Two taps, two server round trips, final state = last server truth.
    verify(remote.toggleLikeBlog('user', 'blog')).called(2);
    expect(
      states.whereType<UserLikedBlogsLoading>(),
      hasLength(1),
      reason: 'the liked list refreshes once per burst, not per tap',
    );
    final last = states.whereType<ToggleBlogLikeSuccess>().last;
    expect(last.isLiked, isFalse);
  });

  test('a failed toggle keeps the queued tap running', () async {
    final connection = MockConnection();
    final remote = MockRemote();
    when(() => connection.isConnected).thenAnswer((_) async => true);

    final List<Future<bool> Function()> answers = [
      () async => throw StateError('first toggle fails'),
      () async => true,
    ];
    var call = 0;
    when(() => remote.toggleLikeBlog('user', 'blog')).thenAnswer((_) {
      final answer = answers[call++];
      return answer();
    });
    when(() => remote.getUserLikedBlogs('user'))
        .thenAnswer((_) async => <BlogModel>[]);

    final repo = BlogRepositoryImpl(remote, MockLocal(), connection);
    final bloc = BlogLikedBloc(
      toggleBlogLike: ToggleLikeBlog(repo),
      isBlogLiked: IsBlogLiked(repo),
      getUserLikedBlogs: GetUserLikedBlogs(repo),
    );
    addTearDown(bloc.close);

    final states = <BlogLikedState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    bloc.add(ToggleBlogLike(userId: 'user', blogId: 'blog'));
    await Future<void>.delayed(Duration.zero);
    bloc.add(ToggleBlogLike(userId: 'user', blogId: 'blog'));
    await bloc.stream.firstWhere((state) => state is UserLikedBlogsSuccess);

    verify(remote.toggleLikeBlog('user', 'blog')).called(2);
    final last = states.whereType<ToggleBlogLikeSuccess>().last;
    expect(last.isLiked, isTrue);
    expect(states.whereType<ToggleBlogLikeFailure>(), hasLength(1));
  });

  test('online toggle success returns the server truth to the UI', () async {
    final connection = MockConnection();
    final remote = MockRemote();
    when(() => connection.isConnected).thenAnswer((_) async => true);
    // Server says the toggle left the blog liked.
    when(() => remote.toggleLikeBlog('user', 'blog'))
        .thenAnswer((_) async => true);
    when(() => remote.getUserLikedBlogs('user'))
        .thenAnswer((_) async => <BlogModel>[]);

    final repo = BlogRepositoryImpl(remote, MockLocal(), connection);
    final bloc = BlogLikedBloc(
      toggleBlogLike: ToggleLikeBlog(repo),
      isBlogLiked: IsBlogLiked(repo),
      getUserLikedBlogs: GetUserLikedBlogs(repo),
    );
    addTearDown(bloc.close);

    final states = <BlogLikedState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    bloc.add(ToggleBlogLike(userId: 'user', blogId: 'blog'));
    await bloc.stream.firstWhere((state) => state is UserLikedBlogsSuccess);

    final emitted = states.whereType<ToggleBlogLikeSuccess>().toList();
    // Optimistic flip, then reconciliation with the server response.
    expect(emitted.first.isLiked, isTrue);
    expect(emitted.last.isLiked, isTrue);
    expect(emitted.last.likedBlogs['blog'], isTrue);
  });
}
