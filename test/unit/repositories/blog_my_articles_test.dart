import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Remote extends Mock implements BlogRemoteDataSource {}

class _Local extends Mock implements BlogLocalDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

BlogModel _blog({bool isDraft = false}) => BlogModel(
  id: 'slug',
  articleId: 'server-id',
  title: 'Title',
  content: 'Content',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2025),
  isDraft: isDraft,
);

void main() {
  late _Remote remote;
  late _Local local;
  late _Connection connection;
  late BlogRepositoryImpl repository;

  setUpAll(() => registerFallbackValue(<BlogModel>[]));
  setUp(() {
    remote = _Remote();
    local = _Local();
    connection = _Connection();
    repository = BlogRepositoryImpl(remote, local, connection);
  });

  test('returns the account list, drafts included', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(
      () => remote.getMyArticles(userId: 'user'),
    ).thenAnswer((_) async => [_blog(isDraft: true), _blog()]);

    final result = await repository.getMyArticles(userId: 'user');
    final blogs = result.getRight().toNullable();

    expect(blogs, isNotNull);
    expect(blogs!.map((blog) => blog.isDraft), [true, false]);
  });

  test('never writes the private list to the shared article cache', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(
      () => remote.getMyArticles(userId: 'user'),
    ).thenAnswer((_) async => [_blog(isDraft: true)]);

    await repository.getMyArticles(userId: 'user');

    // The cache mirrors the public feed: a draft must not reach it.
    verifyNever(() => local.uploadLocalBlogs(blogs: any(named: 'blogs')));
  });

  test(
    'an offline device reports a network failure, not an empty list',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final failure = (await repository.getMyArticles(
        userId: 'user',
      )).getLeft().toNullable();

      expect(failure?.kind, FailureKind.network);
      verifyNever(() => remote.getMyArticles(userId: any(named: 'userId')));
    },
  );

  test('an unsigned-in caller is rejected before any request', () async {
    final failure = (await repository.getMyArticles(
      userId: '',
    )).getLeft().toNullable();

    expect(failure?.kind, FailureKind.auth);
    verifyNever(() => connection.isConnected);
    verifyNever(() => remote.getMyArticles(userId: any(named: 'userId')));
  });

  test('a session switch fails closed instead of returning a list', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.getMyArticles(userId: 'user')).thenThrow(
      const ServerException(
        'account changed',
        kind: FailureKind.auth,
        code: 'auth.sessionChanged',
      ),
    );

    final failure = (await repository.getMyArticles(
      userId: 'user',
    )).getLeft().toNullable();

    expect(failure?.code, 'auth.sessionChanged');
  });
}
