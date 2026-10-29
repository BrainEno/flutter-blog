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

const _kOldCoverUrl =
    'https://demo.supabase.co/storage/v1/object/public/blog_images/'
    'covers/u1/b1/1000000000000.jpg';

const _kNewCoverUrl =
    'https://demo.supabase.co/storage/v1/object/public/blog_images/'
    'covers/u1/b1/1730000000000.jpg';

BlogModel _blog({String imageUrl = _kOldCoverUrl}) => BlogModel(
  id: 'b1',
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
  });

  setUp(() {
    remote = MockRemote();
    local = MockLocal();
    connection = MockConnection();
    repository = BlogRepositoryImpl(remote, local, connection);
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  group('uploadBlog', () {
    test('a failed row insert rolls back the freshly uploaded cover',
        () async {
      when(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          blogId: any(named: 'blogId'),
          posterId: any(named: 'posterId'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(
        () => remote.uploadBlog(any()),
      ).thenThrow(const ServerException('insert rejected'));
      when(
        () => remote.removeBlogImage(_kNewCoverUrl),
      ).thenAnswer((_) async {});

      final result = await repository.uploadBlog(
        image: cover,
        title: '标题',
        content: '正文',
        posterId: 'u1',
        tags: const ['诗歌'],
        imageMimeType: 'image/jpeg',
      );

      expect(result.isLeft(), isTrue);
      verify(() => remote.removeBlogImage(_kNewCoverUrl)).called(1);
    });

    test(
      'a rollback failure is logged, not swallowed: the insert failure '
      'still surfaces',
      () async {
        when(
          () => remote.uploadBlogImage(
            image: any(named: 'image'),
            blogId: any(named: 'blogId'),
            posterId: any(named: 'posterId'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer((_) async => _kNewCoverUrl);
        when(
          () => remote.uploadBlog(any()),
        ).thenThrow(const ServerException('insert rejected'));
        when(
          () => remote.removeBlogImage(_kNewCoverUrl),
        ).thenThrow(const ServerException('storage down'));

        final result = await repository.uploadBlog(
          image: cover,
          title: '标题',
          content: '正文',
          posterId: 'u1',
          tags: const ['诗歌'],
        );

        expect(result.isLeft(), isTrue);
        verify(() => remote.removeBlogImage(_kNewCoverUrl)).called(1);
      },
    );

    test('a successful upload keeps the cover (no rollback)', () async {
      when(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          blogId: any(named: 'blogId'),
          posterId: any(named: 'posterId'),
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
      verifyNever(() => remote.removeBlogImage(any()));
      verify(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          blogId: any(named: 'blogId'),
          posterId: 'u1',
          mimeType: 'image/jpeg',
        ),
      ).called(1);
    });
  });

  group('editBlog', () {
    test(
      'replacing the cover removes the old object only after the DB '
      'update succeeds',
      () async {
        when(() => remote.getBlogById('b1')).thenAnswer((_) async => _blog());
        when(
          () => remote.uploadBlogImage(
            image: any(named: 'image'),
            blogId: any(named: 'blogId'),
            posterId: any(named: 'posterId'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer((_) async => _kNewCoverUrl);
        when(() => remote.editBlog(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as BlogModel,
        );
        when(
          () => remote.removeBlogImage(_kOldCoverUrl),
        ).thenAnswer((_) async {});

        final result = await repository.editBlog(
          blogId: 'b1',
          image: cover,
          title: '新标题',
          content: '新正文',
          tags: const ['诗歌'],
          imageMimeType: 'image/png',
        );

        expect(result.isRight(), isTrue);
        // Order matters: DB update before old-object removal.
        verifyInOrder([
          () => remote.editBlog(any()),
          () => remote.removeBlogImage(_kOldCoverUrl),
        ]);
      },
    );

    test('a failed update rolls back the newly uploaded cover', () async {
      when(() => remote.getBlogById('b1')).thenAnswer((_) async => _blog());
      when(
        () => remote.uploadBlogImage(
          image: any(named: 'image'),
          blogId: any(named: 'blogId'),
          posterId: any(named: 'posterId'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => _kNewCoverUrl);
      when(
        () => remote.editBlog(any()),
      ).thenThrow(const ServerException('rls denied'));
      when(
        () => remote.removeBlogImage(_kNewCoverUrl),
      ).thenAnswer((_) async {});

      final result = await repository.editBlog(
        blogId: 'b1',
        image: cover,
        title: '新标题',
        content: '新正文',
        tags: const ['诗歌'],
      );

      expect(result.isLeft(), isTrue);
      // The old cover must survive - only the new object is rolled back.
      verifyNever(() => remote.removeBlogImage(_kOldCoverUrl));
      verify(() => remote.removeBlogImage(_kNewCoverUrl)).called(1);
    });

    test('editing without a new image touches no storage objects', () async {
      when(() => remote.getBlogById('b1')).thenAnswer((_) async => _blog());
      when(() => remote.editBlog(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as BlogModel,
      );

      final result = await repository.editBlog(
        blogId: 'b1',
        image: null,
        title: '新标题',
        content: '新正文',
        tags: const ['诗歌'],
      );

      expect(result.isRight(), isTrue);
      verifyNever(() => remote.uploadBlogImage(
            image: any(named: 'image'),
            blogId: any(named: 'blogId'),
            posterId: any(named: 'posterId'),
            mimeType: any(named: 'mimeType'),
          ));
      verifyNever(() => remote.removeBlogImage(any()));
    });

    test(
      'an old-cover removal failure does not fail the edit (logged orphan)',
      () async {
        when(() => remote.getBlogById('b1')).thenAnswer((_) async => _blog());
        when(
          () => remote.uploadBlogImage(
            image: any(named: 'image'),
            blogId: any(named: 'blogId'),
            posterId: any(named: 'posterId'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer((_) async => _kNewCoverUrl);
        when(() => remote.editBlog(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as BlogModel,
        );
        when(
          () => remote.removeBlogImage(_kOldCoverUrl),
        ).thenThrow(const ServerException('storage down'));

        final result = await repository.editBlog(
          blogId: 'b1',
          image: cover,
          title: '新标题',
          content: '新正文',
          tags: const ['诗歌'],
        );

        // The DB row already points at the new cover: the edit succeeded.
        expect(result.isRight(), isTrue);
      },
    );
  });
}
