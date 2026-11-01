import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/latest_feed_cursor.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Remote extends Mock implements BlogRemoteDataSource {}

class _Local extends Mock implements BlogLocalDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

BlogModel _blog(int n) => BlogModel(
  id: 'article-$n',
  articleId: _uuid(n),
  title: 'title',
  content: 'body',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2020),
  publishedAt: '2026-11-01T12:34:56.123Z',
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
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(
      () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
    ).thenAnswer((_) async {});
  });

  test(
    'first network page creates an in-memory continuation and is cached',
    () async {
      final blogs = List.generate(10, _blog);
      when(() => remote.getAllBlogs(page: 1)).thenAnswer((_) async => blogs);
      final result = await repository.getAllBlogs(page: 1);
      result.fold((failure) => fail(failure.message), (page) {
        expect(page.source, BlogFeedSource.network);
        expect(page.blogs, blogs);
        final continuation = LatestFeedContinuation.tryDecode(page.nextCursor!);
        expect(continuation!.seenIds, hasLength(10));
      });
      verify(() => local.uploadLocalBlogs(blogs: blogs)).called(1);
      verifyNever(() => remote.getAllBlogsAfter(cursor: any(named: 'cursor')));
    },
  );

  test(
    'later pages forward the opaque token and cache only returned rows',
    () async {
      final fresh = List.generate(10, (index) => _blog(index + 10));
      when(() => remote.getAllBlogsAfter(cursor: 'first-token')).thenAnswer(
        (_) async => LatestFeedSlice(blogs: fresh, nextCursor: 'next-token'),
      );
      final result = await repository.getAllBlogs(
        page: 2,
        source: BlogFeedSource.network,
        cursor: 'first-token',
      );
      result.fold((failure) => fail(failure.message), (page) {
        expect(page.blogs, fresh);
        expect(page.nextCursor, 'next-token');
      });
      verify(() => local.uploadLocalBlogs(blogs: fresh)).called(1);
      verifyNever(() => remote.getAllBlogs(page: 2));
    },
  );

  test(
    'first rejected/ignored cursor falls back and stays on offset',
    () async {
      when(
        () => remote.getAllBlogsAfter(cursor: 'first-token'),
      ).thenThrow(const LatestFeedCursorUnavailable());
      final second = List.generate(10, (index) => _blog(index + 10));
      final third = List.generate(10, (index) => _blog(index + 20));
      when(() => remote.getAllBlogs(page: 2)).thenAnswer((_) async => second);
      when(() => remote.getAllBlogs(page: 3)).thenAnswer((_) async => third);

      final fallback = await repository.getAllBlogs(
        page: 2,
        source: BlogFeedSource.network,
        cursor: 'first-token',
      );
      fallback.fold((failure) => fail(failure.message), (page) {
        expect(page.blogs, second);
        expect(page.nextCursor, isNull);
      });
      final next = await repository.getAllBlogs(
        page: 3,
        source: BlogFeedSource.network,
      );
      next.fold((failure) => fail(failure.message), (page) {
        expect(page.blogs, third);
        expect(page.nextCursor, isNull);
      });
      verify(() => remote.getAllBlogsAfter(cursor: 'first-token')).called(1);
      verify(() => remote.getAllBlogs(page: 2)).called(1);
      verify(() => remote.getAllBlogs(page: 3)).called(1);
    },
  );

  test('does not splice offset into an established cursor session', () async {
    when(
      () => remote.getAllBlogsAfter(cursor: 'next-token'),
    ).thenThrow(const LatestFeedCursorUnavailable());
    final result = await repository.getAllBlogs(
      page: 3,
      source: BlogFeedSource.network,
      cursor: 'next-token',
    );
    result.fold(
      (failure) => expect(failure.code, 'feed.paginationChanged'),
      (_) => fail('expected pagination change failure'),
    );
    verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));
    verifyNever(() => local.uploadLocalBlogs(blogs: any(named: 'blogs')));
  });

  test('a dense boundary is not reported as an empty page', () async {
    when(
      () => remote.getAllBlogsAfter(cursor: 'dense'),
    ).thenThrow(const LatestFeedCursorTooDense());
    final result = await repository.getAllBlogs(
      page: 3,
      source: BlogFeedSource.network,
      cursor: 'dense',
    );
    result.fold(
      (failure) => expect(failure.code, 'feed.paginationDense'),
      (_) => fail('expected pagination density failure'),
    );
    verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));
  });

  test(
    'network failure in a cursor session never falls back to cache or offset',
    () async {
      when(
        () => remote.getAllBlogsAfter(cursor: 'first-token'),
      ).thenThrow(const SocketException('offline'));
      final result = await repository.getAllBlogs(
        page: 2,
        source: BlogFeedSource.network,
        cursor: 'first-token',
      );
      result.fold(
        (failure) => expect(failure.kind, FailureKind.network),
        (_) => fail('expected network failure'),
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

  test(
    'rejects a cursor for first-page or cache requests before I/O',
    () async {
      for (final request in [
        repository.getAllBlogs(page: 1, cursor: 'cursor'),
        repository.getAllBlogs(
          page: 2,
          source: BlogFeedSource.cache,
          cursor: 'cursor',
        ),
      ]) {
        final result = await request;
        result.fold(
          (failure) => expect(failure.kind, FailureKind.validation),
          (_) => fail('expected invalid pagination failure'),
        );
      }
      verifyNever(() => connection.isConnected);
      verifyNever(() => remote.getAllBlogsAfter(cursor: any(named: 'cursor')));
    },
  );
}
