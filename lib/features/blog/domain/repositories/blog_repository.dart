import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:fpdart/fpdart.dart';

abstract interface class BlogRepository {
  /// [image] is the picked cover; null publishes a text-only article.
  Future<Either<Failure, Blog>> uploadBlog({
    required File? image,
    required String title,
    required String content,
    required String posterId,
    required List<String> tags,
    String? imageMimeType,
  });

  /// Soft-deletes the article with the public id [blogId] (slug): it
  /// leaves every list and moves to the author's recycle bin, where the
  /// server purge will remove it for good once the retention window
  /// ends. The offline cache row is evicted on success.
  Future<Either<Failure, bool>> deleteBlog(String blogId);

  /// The author's recycle bin: tombstones most recently deleted first.
  Future<Either<Failure, List<DeletedBlog>>> getDeletedBlogs();

  /// Restores a tombstone by its server article id; the article comes
  /// back as a draft.
  Future<Either<Failure, Blog>> restoreDeletedBlog(String articleId);

  Future<Either<Failure, List<Blog>>> getAllBlogs({required int page});

  Future<Either<Failure, Blog>> getBlogById(String blogId);

  Future<Either<Failure, List<Blog>>> getBlogsByTag(String tag);

  Future<Either<Failure, List<Blog>>> searchBlogs(String query);

  Future<Either<Failure, List<Blog>>> getBlogsByUser(String userId);

  Future<Either<Failure, Blog>> editBlog({
    required String blogId,
    required String title,
    required String content,
    required List<String> tags,
    required File? image,
    String? imageMimeType,
  });

  Future<Either<Failure, bool>> toggleLikeBlog(String userId, String blogId);

  Future<Either<Failure, bool>> isBlogLiked(String userId, String blogId);

  Future<Either<Failure, List<Blog>>> getUserLikedBlogs(String userId);
}
