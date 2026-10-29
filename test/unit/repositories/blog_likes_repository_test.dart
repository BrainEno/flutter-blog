import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements BlogRemoteDataSource {}

class MockLocal extends Mock implements BlogLocalDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  late MockRemote remote;
  late MockConnection connection;
  late BlogRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    repository = BlogRepositoryImpl(remote, MockLocal(), connection);
  });

  test('offline toggle returns failure without calling the server', () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);
    final result = await repository.toggleLikeBlog('user', 'blog');
    result.fold(
      (failure) => expect(failure.message, contains('收藏未同步')),
      (_) => fail('offline toggle must not succeed'),
    );
    verifyNever(() => remote.toggleLikeBlog(any(), any()));
  });

  test('offline status and list return failures without server calls',
      () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);
    final status = await repository.isBlogLiked('user', 'blog');
    final list = await repository.getUserLikedBlogs('user');
    expect(status.isLeft(), isTrue);
    expect(list.isLeft(), isTrue);
    verifyNever(() => remote.isBlogLikedByUser(any(), any()));
    verifyNever(() => remote.getUserLikedBlogs(any()));
  });

  test('list server exception is returned rather than thrown', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.getUserLikedBlogs('user'))
        .thenThrow(const ServerException('server unavailable'));
    final result = await repository.getUserLikedBlogs('user');
    result.fold(
      (failure) => expect(failure.message, 'server unavailable'),
      (_) => fail('expected failure'),
    );
  });

  test('unexpected connectivity and datasource errors become safe failures',
      () async {
    when(() => connection.isConnected).thenThrow(StateError('private details'));
    final toggle = await repository.toggleLikeBlog('user', 'blog');
    toggle.fold(
      (failure) => expect(failure.message, isNot(contains('private details'))),
      (_) => fail('expected failure'),
    );
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.isBlogLikedByUser('user', 'blog'))
        .thenThrow(StateError('private details'));
    when(() => remote.getUserLikedBlogs('user'))
        .thenThrow(StateError('private details'));
    final status = await repository.isBlogLiked('user', 'blog');
    final list = await repository.getUserLikedBlogs('user');
    status.fold(
      (failure) => expect(failure.message, isNot(contains('private details'))),
      (_) => fail('expected failure'),
    );
    list.fold(
      (failure) => expect(failure.message, isNot(contains('private details'))),
      (_) => fail('expected failure'),
    );
  });

  test('online results and known errors keep their contracts', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.toggleLikeBlog('user', 'blog'))
        .thenAnswer((_) async => true);
    when(() => remote.isBlogLikedByUser('user', 'blog'))
        .thenAnswer((_) async => false);
    when(() => remote.getUserLikedBlogs('user'))
        .thenAnswer((_) async => <BlogModel>[]);
    expect((await repository.toggleLikeBlog('user', 'blog')).isRight(), isTrue);
    (await repository.isBlogLiked('user', 'blog')).fold(
      (_) => fail('expected success'),
      (liked) => expect(liked, isFalse),
    );
    (await repository.getUserLikedBlogs('user')).fold(
      (_) => fail('expected success'),
      (blogs) => expect(blogs, isEmpty),
    );
    when(() => remote.toggleLikeBlog('user', 'blog'))
        .thenThrow(const ServerException('rejected'));
    (await repository.toggleLikeBlog('user', 'blog')).fold(
      (failure) => expect(failure.message, 'rejected'),
      (_) => fail('expected failure'),
    );
  });
}
