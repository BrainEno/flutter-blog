import 'dart:io';

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

BlogModel _blog() => BlogModel(
  id: 'slug',
  articleId: 'server-id',
  title: 'Title',
  content: 'Content',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2025),
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

  test('offline detail and search surface local read failures', () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);
    when(() => local.loadBlogById('slug')).thenThrow(StateError('private'));
    when(
      () => local.searchLocalBlogs('query'),
    ).thenThrow(StateError('private'));

    for (final failure in [
      (await repository.getBlogById('slug')).getLeft().toNullable(),
      (await repository.searchBlogs('query')).getLeft().toNullable(),
    ]) {
      expect(failure?.kind, FailureKind.storage);
      expect(failure?.message, isNot(contains('private')));
    }
    verifyNever(() => remote.getBlogById(any()));
    verifyNever(() => remote.searchBlogs(any()));
  });

  test(
    'successful detail fetch reports cache write failure as storage',
    () async {
      final blog = _blog();
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.getBlogById('slug')).thenAnswer((_) async => blog);
      when(
        () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
      ).thenThrow(StateError('private'));

      final result = await repository.getBlogById('slug');
      final failure = result.getLeft().toNullable();
      expect(failure?.kind, FailureKind.storage);
      expect(failure?.message, isNot(contains('private')));
    },
  );

  test('probe failures follow the repository Failure contract', () async {
    when(() => connection.isConnected).thenThrow(const SocketException('lost'));

    final detail = await repository.getBlogById('slug');
    final search = await repository.searchBlogs('query');
    final publish = await repository.uploadBlog(
      title: 'Title',
      content: 'Content',
      posterId: 'author',
      tags: const [],
    );
    expect(detail.getLeft().toNullable()?.kind, FailureKind.network);
    expect(search.getLeft().toNullable()?.kind, FailureKind.network);
    expect(publish.getLeft().toNullable()?.kind, FailureKind.network);
    verifyNever(() => remote.getBlogById(any()));
  });

  test('server permission errors are not hidden as offline results', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(
      () => remote.getBlogById('slug'),
    ).thenThrow(const ServerException('denied', kind: FailureKind.permission));
    final result = await repository.getBlogById('slug');
    expect(result.getLeft().toNullable()?.kind, FailureKind.permission);
    verifyNever(() => local.loadBlogById(any()));
  });

  test('delete does not contact server if cache lookup failed', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => local.loadBlogById('slug')).thenThrow(StateError('read failed'));
    final result = await repository.deleteBlog('slug');
    expect(result.getLeft().toNullable()?.kind, FailureKind.storage);
    verifyNever(() => remote.deleteArticle(any()));
  });

  test(
    'delete reports that server committed if cache eviction fails',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => local.loadBlogById('slug')).thenAnswer((_) async => _blog());
      when(
        () => remote.deleteArticle('server-id'),
      ).thenAnswer((_) async => true);
      when(
        () => local.deleteCachedBlog('slug'),
      ).thenThrow(StateError('private'));

      final result = await repository.deleteBlog('slug');
      final failure = result.getLeft().toNullable();
      expect(failure?.kind, FailureKind.storage);
      expect(failure?.code, 'article.deletedCacheFailed');
      expect(failure?.message, isNot(contains('private')));
      verify(() => remote.deleteArticle('server-id')).called(1);
    },
  );
}
