import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';
import 'package:belog/features/blog/data/repositories/comment_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCommentRemote extends Mock implements CommentRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

CommentModel _comment(String id) => CommentModel(
  id: id,
  articleId: 'server-uuid-1',
  authorId: 'u1',
  content: '评论$id',
  createdAt: DateTime.utc(2025),
);

void main() {
  late MockCommentRemote remote;
  late MockConnection connection;
  late CommentRepositoryImpl repository;

  setUp(() {
    remote = MockCommentRemote();
    connection = MockConnection();
    repository = CommentRepositoryImpl(
      commentRemoteDataSource: remote,
      connectionChecker: connection,
    );
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  group('getComments', () {
    test('returns the thread on success', () async {
      when(
        () => remote.getComments('my-slug'),
      ).thenAnswer((_) async => [_comment('c1'), _comment('c2')]);

      final result = await repository.getComments('my-slug');

      expect(
        result.fold(
          (failure) => fail('expected success'),
          (comments) => comments.map((c) => c.id).toList(),
        ),
        ['c1', 'c2'],
      );
    });

    test('offline returns a network failure without calling the server',
        () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.getComments('my-slug');

      result.fold(
        (failure) => expect(failure.code, 'network.offline'),
        (_) => fail('offline load must not succeed'),
      );
      verifyNever(() => remote.getComments(any()));
    });

    test('server exceptions are returned rather than thrown', () async {
      when(() => remote.getComments('my-slug')).thenThrow(
        const ServerException('评论加载失败'),
      );

      final result = await repository.getComments('my-slug');

      result.fold(
        (failure) => expect(failure.message, '评论加载失败'),
        (_) => fail('expected failure'),
      );
    });
  });

  group('createComment', () {
    test('forwards the idempotency key to the datasource', () async {
      when(
        () => remote.createComment(
          slug: 'my-slug',
          content: '你好',
          parentCommentId: null,
          idempotencyKey: 'key-1',
        ),
      ).thenAnswer((_) async => _comment('c9'));

      final result = await repository.createComment(
        slug: 'my-slug',
        content: '你好',
        parentCommentId: null,
        idempotencyKey: 'key-1',
      );

      expect(result.isRight(), isTrue);
      verify(
        () => remote.createComment(
          slug: 'my-slug',
          content: '你好',
          parentCommentId: null,
          idempotencyKey: 'key-1',
        ),
      ).called(1);
    });

    test('offline returns a message that names the comment', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.createComment(
        slug: 'my-slug',
        content: '你好',
        parentCommentId: null,
        idempotencyKey: 'key-1',
      );

      result.fold(
        (failure) => expect(failure.message, contains('评论未发送')),
        (_) => fail('offline submit must not succeed'),
      );
      verifyNever(
        () => remote.createComment(
          slug: any(),
          content: any(),
          parentCommentId: any(),
          idempotencyKey: any(),
        ),
      );
    });
  });

  group('deleteComment', () {
    test('returns right on success', () async {
      when(() => remote.deleteComment('c1')).thenAnswer((_) async => true);

      final result = await repository.deleteComment('c1');

      expect(result.isRight(), isTrue);
    });

    test('offline returns a failure without calling the server', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.deleteComment('c1');

      expect(result.isLeft(), isTrue);
      verifyNever(() => remote.deleteComment(any()));
    });
  });
}
