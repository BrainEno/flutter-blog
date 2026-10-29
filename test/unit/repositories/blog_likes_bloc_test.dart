import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements BlogRemoteDataSource {}

class MockLocal extends Mock implements BlogLocalDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  test('offline toggle rolls back optimistic state and reports failure',
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

    expect(states, hasLength(2));
    expect(states.first, isA<ToggleBlogLikeSuccess>());
    expect(states.first.likedBlogs['blog'], isTrue);
    final failure = states.last as ToggleBlogLikeFailure;
    expect(failure.likedBlogs['blog'], isFalse);
    expect(failure.error, contains('收藏未同步'));
    verifyNever(() => remote.toggleLikeBlog(any(), any()));
  });
}
