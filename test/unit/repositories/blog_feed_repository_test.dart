import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Remote extends Mock implements BlogRemoteDataSource {}

class _Local extends Mock implements BlogLocalDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

BlogModel _blog(String id) => BlogModel(
  id: id,
  title: 'title $id',
  content: 'body',
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

  test('offline pages use the correct bounded SQLite offsets', () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);
    when(
      () => local.loadBlogs(limit: kBlogPageSize, offset: 0),
    ).thenAnswer((_) async => [_blog('first')]);
    when(
      () => local.loadBlogs(limit: kBlogPageSize, offset: 10),
    ).thenAnswer((_) async => [_blog('second')]);
    when(
      () => local.loadBlogs(limit: kBlogPageSize, offset: 20),
    ).thenAnswer((_) async => []);

    final first = await repository.getAllBlogs(page: 1);
    final second = await repository.getAllBlogs(
      page: 2,
      source: BlogFeedSource.cache,
    );
    final third = await repository.getAllBlogs(
      page: 3,
      source: BlogFeedSource.cache,
    );

    first.fold((f) => fail(f.message), (page) {
      expect(page.source, BlogFeedSource.cache);
      expect(page.blogs.single.id, 'first');
    });
    second.fold((f) => fail(f.message), (page) {
      expect(page.source, BlogFeedSource.cache);
      expect(page.blogs.single.id, 'second');
    });
    third.fold((f) => fail(f.message), (page) {
      expect(page.source, BlogFeedSource.cache);
      expect(page.blogs, isEmpty);
    });
    verify(() => connection.isConnected).called(1);
    verify(() => local.loadBlogs(limit: kBlogPageSize, offset: 0)).called(1);
    verify(() => local.loadBlogs(limit: kBlogPageSize, offset: 10)).called(1);
    verify(() => local.loadBlogs(limit: kBlogPageSize, offset: 20)).called(1);
    verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));
  });

  test(
    'a cached session remains local even after connectivity returns',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => local.loadBlogs(limit: kBlogPageSize, offset: 10),
      ).thenAnswer((_) async => [_blog('cached')]);

      final result = await repository.getAllBlogs(
        page: 2,
        source: BlogFeedSource.cache,
      );

      result.fold((f) => fail(f.message), (page) {
        expect(page.source, BlogFeedSource.cache);
        expect(page.blogs.single.id, 'cached');
      });
      verifyNever(() => connection.isConnected);
      verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));
    },
  );

  test('online page is cached and marked as network data', () async {
    final blogs = [_blog('online')];
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.getAllBlogs(page: 1)).thenAnswer((_) async => blogs);
    when(() => local.uploadLocalBlogs(blogs: blogs)).thenAnswer((_) async {});

    final result = await repository.getAllBlogs(page: 1);

    result.fold((f) => fail(f.message), (page) {
      expect(page.source, BlogFeedSource.network);
      expect(page.blogs, blogs);
    });
    verifyInOrder([
      () => remote.getAllBlogs(page: 1),
      () => local.uploadLocalBlogs(blogs: blogs),
    ]);
    verifyNever(
      () => local.loadBlogs(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    );
  });

  test(
    'a network-pinned session reports disconnection, not cached pages',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.getAllBlogs(
        page: 2,
        source: BlogFeedSource.network,
      );

      result.fold(
        (f) => expect(f.kind, FailureKind.network),
        (_) => fail('expected failure'),
      );
      verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));
      verifyNever(
        () => local.loadBlogs(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      );
    },
  );

  for (final error in [
    const SocketException('connection lost'),
    TimeoutException('timeout'),
    const ServerException('connection lost', kind: FailureKind.network),
  ]) {
    test('initial page falls back to cache on ${error.runtimeType}', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.getAllBlogs(page: 1)).thenThrow(error);
      when(
        () => local.loadBlogs(limit: kBlogPageSize, offset: 0),
      ).thenAnswer((_) async => [_blog('cached')]);

      final result = await repository.getAllBlogs(page: 1);

      result.fold((f) => fail(f.message), (page) {
        expect(page.source, BlogFeedSource.cache);
        expect(page.blogs.single.id, 'cached');
      });
      verify(() => local.loadBlogs(limit: kBlogPageSize, offset: 0)).called(1);
      verifyNever(() => local.uploadLocalBlogs(blogs: any(named: 'blogs')));
    });
  }

  test(
    'network-pinned page reports a socket failure instead of falling back',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.getAllBlogs(page: 2),
      ).thenThrow(const SocketException('lost'));

      final result = await repository.getAllBlogs(
        page: 2,
        source: BlogFeedSource.network,
      );

      result.fold(
        (f) => expect(f.kind, FailureKind.network),
        (_) => fail('expected failure'),
      );
      verifyNever(
        () => local.loadBlogs(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      );
    },
  );

  for (final kind in [
    FailureKind.auth,
    FailureKind.permission,
    FailureKind.server,
  ]) {
    test('does not hide a $kind error behind cached data', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.getAllBlogs(page: 1),
      ).thenThrow(ServerException('rejected', kind: kind));

      final result = await repository.getAllBlogs(page: 1);

      result.fold((f) => expect(f.kind, kind), (_) => fail('expected failure'));
      verifyNever(
        () => local.loadBlogs(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      );
    });
  }

  test(
    'local read and write errors are reported as storage failures',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(
        () => local.loadBlogs(limit: kBlogPageSize, offset: 0),
      ).thenThrow(StateError('read failed'));
      final read = await repository.getAllBlogs(page: 1);
      read.fold(
        (f) => expect(f.kind, FailureKind.storage),
        (_) => fail('expected failure'),
      );

      when(() => connection.isConnected).thenAnswer((_) async => true);
      final blogs = [_blog('online')];
      when(() => remote.getAllBlogs(page: 1)).thenAnswer((_) async => blogs);
      when(
        () => local.uploadLocalBlogs(blogs: blogs),
      ).thenThrow(StateError('write failed'));
      final write = await repository.getAllBlogs(page: 1);
      write.fold(
        (f) => expect(f.kind, FailureKind.storage),
        (_) => fail('expected failure'),
      );
    },
  );

  test('invalid pages fail before touching the network or storage', () async {
    for (final page in [0, -1]) {
      final result = await repository.getAllBlogs(page: page);
      result.fold(
        (f) => expect(f.kind, FailureKind.validation),
        (_) => fail('expected failure'),
      );
    }
    verifyNever(() => connection.isConnected);
    verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));
    verifyNever(
      () => local.loadBlogs(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    );
  });
}
