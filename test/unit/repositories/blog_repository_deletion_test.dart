import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements BlogRemoteDataSource {}

class MockLocal extends Mock implements BlogLocalDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

BlogModel _blog({String id = 'my-slug', String articleId = 'server-uuid-1'}) =>
    BlogModel(
      id: id,
      articleId: articleId,
      title: '标题',
      content: '正文',
      posterId: 'u1',
      imageUrl: '',
      tags: const ['诗歌'],
      updatedAt: DateTime.utc(2025),
    );

DeletedBlog _tombstone() => DeletedBlog(
  articleId: 'server-uuid-1',
  title: '被删的文章',
  imageUrl: '',
  deletedAt: DateTime.utc(2026, 10, 1),
  purgesAt: DateTime.utc(2026, 10, 31),
);

void main() {
  late MockRemote remote;
  late MockLocal local;
  late MockConnection connection;
  late BlogRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    local = MockLocal();
    connection = MockConnection();
    repository = BlogRepositoryImpl(remote, local, connection);
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  group('deleteBlog', () {
    test(
      'resolves the UUID from the cache and never fetches remotely',
      () async {
        when(
          () => local.loadBlogById('my-slug'),
        ).thenAnswer((_) async => _blog());
        when(
          () => remote.deleteArticle('server-uuid-1'),
        ).thenAnswer((_) async => true);
        when(() => local.deleteCachedBlog('my-slug')).thenAnswer((_) async {});

        final result = await repository.deleteBlog('my-slug');

        expect(result.isRight(), isTrue);
        verify(() => remote.deleteArticle('server-uuid-1')).called(1);
        verifyNever(() => remote.getBlogById(any()));
        verify(() => local.deleteCachedBlog('my-slug')).called(1);
      },
    );

    test('falls back to a remote fetch when the cache misses', () async {
      when(() => local.loadBlogById('my-slug')).thenAnswer((_) async => null);
      when(
        () => remote.getBlogById('my-slug'),
      ).thenAnswer((_) async => _blog());
      when(
        () => remote.deleteArticle('server-uuid-1'),
      ).thenAnswer((_) async => true);
      when(() => local.deleteCachedBlog('my-slug')).thenAnswer((_) async {});

      final result = await repository.deleteBlog('my-slug');

      expect(result.isRight(), isTrue);
      verify(() => remote.getBlogById('my-slug')).called(1);
      verify(() => local.deleteCachedBlog('my-slug')).called(1);
    });

    test('a failed delete keeps the cached row', () async {
      when(
        () => local.loadBlogById('my-slug'),
      ).thenAnswer((_) async => _blog());
      when(() => remote.deleteArticle('server-uuid-1')).thenThrow(
        const ServerException('相关数据不存在或已被删除', kind: FailureKind.validation),
      );

      final result = await repository.deleteBlog('my-slug');

      expect(result.isLeft(), isTrue);
      verifyNever(() => local.deleteCachedBlog(any()));
    });

    test('an offline device fails fast without touching the sources', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.deleteBlog('my-slug');

      expect(
        result.fold(
          (failure) => failure.kind == FailureKind.network,
          (_) => false,
        ),
        isTrue,
      );
      verifyNever(() => remote.deleteArticle(any()));
    });
  });

  group('getDeletedBlogs', () {
    test('passes the tombstones through', () async {
      when(
        () => remote.getDeletedBlogs(),
      ).thenAnswer((_) async => [_tombstone()]);

      final result = await repository.getDeletedBlogs();

      expect(result.getRight().toNullable(), hasLength(1));
    });

    test('an offline device reports the network failure', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.getDeletedBlogs();

      expect(result.isLeft(), isTrue);
      verifyNever(() => remote.getDeletedBlogs());
    });
  });

  group('restoreDeletedBlog', () {
    test('returns the restored draft', () async {
      when(
        () => remote.restoreArticle('server-uuid-1'),
      ).thenAnswer((_) async => _blog());

      final result = await repository.restoreDeletedBlog('server-uuid-1');

      expect(result.getRight().toNullable()?.id, 'my-slug');
    });

    test('a rejected restore surfaces the failure', () async {
      when(() => remote.restoreArticle('server-uuid-1')).thenThrow(
        const ServerException('没有权限执行此操作', kind: FailureKind.permission),
      );

      final result = await repository.restoreDeletedBlog('server-uuid-1');

      expect(result.isLeft(), isTrue);
    });
  });
}
