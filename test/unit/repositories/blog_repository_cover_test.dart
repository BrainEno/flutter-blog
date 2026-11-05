import 'dart:typed_data';

import 'package:belog/core/common/entities/image_upload.dart';
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

BlogModel _blog({
  String imageUrl = _kOldCoverUrl,
  bool plainEditorCompatible = true,
  String? serverSummary = '作者的摘要',
}) => BlogModel(
  id: 'my-slug',
  articleId: 'b1',
  plainEditorCompatible: plainEditorCompatible,
  serverSummary: serverSummary,
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
  final cover = ImageUpload(bytes: Uint8List(3), mimeType: 'image/jpeg');

  setUpAll(() {
    registerFallbackValue(_blog());
    registerFallbackValue(cover);
  });

  setUp(() {
    remote = MockRemote();
    local = MockLocal();
    connection = MockConnection();
    repository = BlogRepositoryImpl(remote, local, connection);
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  group('uploadBlog', () {
    test('uploads the cover first, then creates the article with it', () async {
      when(
        () => remote.uploadBlogImage(image: any(named: 'image')),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(
        () => remote.uploadBlog(
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.uploadBlog(
        image: cover,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
      );

      expect(result.isRight(), isTrue);
      // Capture through verifyInOrder: a separate verify() afterwards
      // cannot match calls the in-order check already consumed.
      final order = verifyInOrder([
        () => remote.uploadBlogImage(image: any(named: 'image')),
        () => remote.uploadBlog(
          captureAny(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ]);
      final created = order.last.captured.single as BlogModel;
      expect(created.imageUrl, _kNewCoverUrl);
      expect(created.title, '标题');
    });

    test('a coverless publish skips the media upload entirely (#17)', () async {
      when(
        () => remote.uploadBlog(
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.uploadBlog(
        image: null,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const [],
      );

      expect(result.isRight(), isTrue);
      verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
      final captures = verify(
        () => remote.uploadBlog(
          captureAny(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).captured;
      final created = captures.single as BlogModel;
      expect(created.imageUrl, '');
    });

    test('a failed article create surfaces the failure (media is '
        'server-managed, nothing to roll back client-side)', () async {
      when(
        () => remote.uploadBlogImage(image: any(named: 'image')),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(
        () => remote.uploadBlog(
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(const ServerException('insert rejected'));

      final result = await repository.uploadBlog(
        image: cover,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
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
      verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
      verifyNever(
        () => remote.uploadBlog(
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      );
    });
  });

  group('uploadCover', () {
    test('returns the URL the server stored the asset at', () async {
      when(
        () => remote.uploadBlogImage(image: any(named: 'image')),
      ).thenAnswer((_) async => _kNewCoverUrl);

      final result = await repository.uploadCover(image: cover);

      expect(result.fold((_) => null, (url) => url), _kNewCoverUrl);
    });

    test('offline fails fast without touching the server', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.uploadCover(image: cover);

      expect(result.isLeft(), isTrue);
      verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
    });

    test('a rejected upload surfaces the failure', () async {
      when(
        () => remote.uploadBlogImage(image: any(named: 'image')),
      ).thenThrow(const ServerException('media rejected'));

      final result = await repository.uploadCover(image: cover);

      expect(result.isLeft(), isTrue);
    });
  });

  group('uploadBlog with an already uploaded cover', () {
    test('reuses the URL instead of uploading the bytes again', () async {
      when(
        () => remote.uploadBlog(
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.uploadBlog(
        image: cover,
        uploadedCoverUrl: _kNewCoverUrl,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
      );

      expect(result.isRight(), isTrue);
      verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
      final BlogModel created = verify(
        () => remote.uploadBlog(
          captureAny(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).captured.single;
      expect(created.imageUrl, _kNewCoverUrl);
      expect(created.title, '标题');
    });
  });

  group('editBlog', () {
    test(
      'rejects unsupported structures before uploading or writing',
      () async {
        when(
          () => remote.getBlogById('my-slug'),
        ).thenAnswer((_) async => _blog(plainEditorCompatible: false));

        final result = await repository.editBlog(
          blogId: 'my-slug',
          image: cover,
          title: '新标题',
          content: '新正文',
          tags: const ['诗歌'],
        );

        result.fold(
          (failure) =>
              expect(failure.code, 'article.structuredEditUnsupported'),
          (_) => fail('unsupported content must not be overwritten'),
        );
        verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
        verifyNever(() => remote.editBlog(any()));
      },
    );

    test('unknown server summary also blocks the cover and edit', () async {
      when(
        () => remote.getBlogById('my-slug'),
      ).thenAnswer((_) async => _blog(serverSummary: null));

      final result = await repository.editBlog(
        blogId: 'my-slug',
        image: cover,
        title: '新标题',
        content: '正文',
        tags: const [],
      );

      expect(result.isLeft(), isTrue);
      verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
      verifyNever(() => remote.editBlog(any()));
    });

    test('fetches the article, uploads a new cover, then updates', () async {
      when(
        () => remote.getBlogById('my-slug'),
      ).thenAnswer((_) async => _blog());
      when(
        () => remote.uploadBlogImage(image: any(named: 'image')),
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
      );

      expect(result.isRight(), isTrue);
      final order = verifyInOrder([
        () => remote.getBlogById('my-slug'),
        () => remote.uploadBlogImage(image: any(named: 'image')),
        () => remote.editBlog(captureAny()),
      ]);
      final updated = order.last.captured.single as BlogModel;
      expect(updated.imageUrl, _kNewCoverUrl);
      expect(updated.serverSummary, '作者的摘要');
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
      verifyNever(() => remote.uploadBlogImage(image: any(named: 'image')));
      final updated =
          verify(() => remote.editBlog(captureAny())).captured.single
              as BlogModel;
      expect(updated.imageUrl, _kOldCoverUrl);
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
