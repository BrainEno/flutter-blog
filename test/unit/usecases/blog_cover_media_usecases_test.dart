import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockBlogRepository extends Mock implements BlogRepository {}

void main() {
  const fence = NowaveSessionFence(userId: 'user-a', generation: 4);
  const coverUrl = 'https://api.example.invalid/api/v1/media/asset-1';
  final blog = Blog(
    id: 'article-1',
    title: 'Title',
    content: 'Body',
    posterId: 'user-a',
    imageUrl: coverUrl,
    tags: const [],
    updatedAt: DateTime.utc(2026),
  );

  late _MockBlogRepository repository;

  setUp(() {
    repository = _MockBlogRepository();
  });

  test('UploadBlog forwards a selected immutable cover URL', () async {
    when(
      () => repository.uploadBlog(
        image: null,
        uploadedCoverUrl: coverUrl,
        title: 'Title',
        content: 'Body',
        posterId: 'user-a',
        tags: const [],
        sessionFence: fence,
        idempotencyKey: 'intent-1',
        categoryIds: null,
      ),
    ).thenAnswer((_) async => right(blog));

    final result = await UploadBlog(repository)(
      UploadBlogParams(
        image: null,
        uploadedCoverUrl: coverUrl,
        title: 'Title',
        content: 'Body',
        posterId: 'user-a',
        tags: const [],
        sessionFence: fence,
        idempotencyKey: 'intent-1',
      ),
    );

    expect(result.getRight().toNullable(), same(blog));
    verify(
      () => repository.uploadBlog(
        image: null,
        uploadedCoverUrl: coverUrl,
        title: 'Title',
        content: 'Body',
        posterId: 'user-a',
        tags: const [],
        sessionFence: fence,
        idempotencyKey: 'intent-1',
        categoryIds: null,
      ),
    ).called(1);
  });

  test('UpdateBlog forwards a selected immutable cover URL', () async {
    when(
      () => repository.editBlog(
        blogId: 'article-1',
        title: 'Title',
        content: 'Body',
        tags: const [],
        image: null,
        uploadedCoverUrl: coverUrl,
        locale: 'zh-CN',
        sessionFence: fence,
        categoryIds: null,
      ),
    ).thenAnswer((_) async => right(blog));

    final result = await UpdateBlog(repository)(
      UpdateBlogParams(
        blogId: 'article-1',
        title: 'Title',
        content: 'Body',
        tags: const [],
        uploadedCoverUrl: coverUrl,
        locale: 'zh-CN',
        sessionFence: fence,
      ),
    );

    expect(result.getRight().toNullable(), same(blog));
    verify(
      () => repository.editBlog(
        blogId: 'article-1',
        title: 'Title',
        content: 'Body',
        tags: const [],
        image: null,
        uploadedCoverUrl: coverUrl,
        locale: 'zh-CN',
        sessionFence: fence,
        categoryIds: null,
      ),
    ).called(1);
  });
}
