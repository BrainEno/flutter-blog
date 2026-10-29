import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:fpdart/fpdart.dart';

abstract interface class BlogRepository {
  Future<Either<Failure, Blog>> uploadBlog({
    required File image,
    required String title,
    required String content,
    required String posterId,
    required List<String> tags,
    String? imageMimeType,
  });

  Future<Either<Failure, bool>> deleteBlog(String blogId);

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
