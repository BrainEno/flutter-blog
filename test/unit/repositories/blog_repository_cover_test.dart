import 'dart:io';

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

const _kOldCoverUrl = 'https://api.example.invalid/api/v1/media/old-asset';
const _kNewCoverUrl = 'https://api.example.invalid/api/v1/media/new-asset';

BlogModel _blog({String imageUrl = _kOldCoverUrl}) => BlogModel(
  id: 'my-slug',
  articleId: 'b1',
  title: '标题',
  content: '正文',
  posterId: 'u1',
  imageUrl: imageUrl,
  tags: const ['诗歌'],
  updatedAt: DateTime.utc(2025),
);

void main() {
  late MockRemote remote;
  late MockLocal local;
  late MockConnection connection;
  late BlogRepositoryImpl repository;
  final cover = File('/nonexistent.jpg');

  setUpAll(() {
    registerFallbackValue(_blog());
    registerFallbackValue(File('/nonexistent.jpg'));
  });

  setUp(() {
    remote = MockRemote();
    local = MockLocal();
    connection = MockConnection();
    repository = BlogRepositoryImpl(remote, local, connection);
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  group('uploadBlog', () {
    test('uploads the cover first, then creates the article with it',
        () async {
      when(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(() => remote.uploadBlog(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.uploadBlog(
        image: cover,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
        imageMimeType: 'image/jpeg',
      );

      expect(result.isRight(), isTrue);
      // Capture through verifyInOrder: a separate verify() afterwards
      // cannot match calls the in-order check already consumed.
      final order = verifyInOrder([
        () => remote.uploadBlogImage(
              image: any(named: 'image'),
              mimeType: 'image/jpeg',
            ),
        () => remote.uploadBlog(captureAny()),
      ]);
      final created = order.last.captured.single as BlogModel;
      expect(created.imageUrl, _kNewCoverUrl);
      expect(created.title, '标题');
    });

    test('a failed article create surfaces the failure (media is '
        'server-managed, nothing to roll back client-side)', () async {
      when(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(
        () => remote.uploadBlog(any()),
      ).thenThrow(const ServerException('insert rejected'));

      final result = await repository.uploadBlog(
        image: cover,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
        imageMimeType: 'image/jpeg',
      );

      expect(result.isLeft(), isTrue);
    });

    test('offline upload fails fast without touching the server', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.uploadBlog(
        image: cover,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
      );

      expect(result.isLeft(), isTrue);
      verifyNever(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          mimeType: any(named: 'mimeType'),
        ),
      );
      verifyNever(() => remote.uploadBlog(any()));
    });
  });

  group('editBlog', () {
    test('fetches the article, uploads a new cover, then updates', () async {
      when(
        () => remote.getBlogById('my-slug'),
      ).thenAnswer((_) async => _blog());
      when(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(() => remote.editBlog(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.editBlog(
        blogId: 'my-slug',
        image: cover,
        title: '新标题',
        content: '新正文',
        tags: const ['诗歌'],
        imageMimeType: 'image/png',
      );

      expect(result.isRight(), isTrue);
      final order = verifyInOrder([
        () => remote.getBlogById('my-slug'),
        () => remote.uploadBlogImage(
              image: any(named: 'image'),
              mimeType: 'image/png',
            ),
        () => remote.editBlog(captureAny()),
      ]);
      final updated = order.last.captured.single as BlogModel;
      expect(updated.imageUrl, _kNewCoverUrl);
      expect(updated.articleId, 'b1');
      expect(updated.id, 'my-slug');
      expect(updated.title, '新标题');
    });

    test('editing without a new image keeps the existing cover', () async {
      when(
        () => remote.getBlogById('my-slug'),
      ).thenAnswer((_) async => _blog());
      when(() => remote.editBlog(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.editBlog(
        blogId: 'my-slug',
        image: null,
        title: '新标题',
        content: '新正文',
        tags: const ['诗歌'],
      );

      expect(result.isRight(), isTrue);
      verifyNever(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          mimeType: any(named: 'mimeType'),
        ),
      );
      final updated = verify(() => remote.editBlog(captureAny())).captured
          .single as BlogModel;
      expect(updated.imageUrl, _kOldCoverUrl);
    });
  });

  group('deleteBlog', () {
    test('reports the backend gap as a validation failure', () async {
      when(
        () => remote.deleteBlog('my-slug'),
      ).thenThrow(const ServerException('当前后端暂不支持删除文章，敬请期待'));

      final result = await repository.deleteBlog('my-slug');

      result.fold(
        (failure) => expect(failure.message, contains('暂不支持删除')),
        (_) => fail('expected a failure'),
      );
    });
  });

  group('getBlogById', () {
    test('caches a fetched article locally', () async {
      when(
        () => remote.getBlogById('my-slug'),
      ).thenAnswer((_) async => _blog());
      when(
        () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
      ).thenAnswer((_) async {});

      final result = await repository.getBlogById('my-slug');

      expect(result.isRight(), isTrue);
      verify(
        () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
      ).called(1);
    });
  });
}
