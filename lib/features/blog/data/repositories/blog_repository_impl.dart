import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class BlogRepositoryImpl implements BlogRepository {
  final BlogRemoteDataSource blogRemoteDataSource;
  final BlogLocalDataSource blogLocalDataSource;
  final ConnectionChecker connectionChecker;

  const BlogRepositoryImpl(
    this.blogRemoteDataSource,
    this.blogLocalDataSource,
    this.connectionChecker,
  );

  @override
  Future<Either<Failure, Blog>> uploadBlog({
    required File image,
    required String title,
    required String content,
    required String posterId,
    required List<String> tags,
    String? imageMimeType,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      // Media assets are immutable and addressed by their own id, so the
      // cover is uploaded first and the article row is created with it.
      // A failure between the two only leaves an unreferenced asset (the
      // backend has no delete endpoint; its lifecycle is managed
      // server-side).
      final imageUrl = await blogRemoteDataSource.uploadBlogImage(
        image: image,
        mimeType: imageMimeType,
      );
      final blogModel = BlogModel(
        id: '',
        title: title,
        content: content,
        posterId: posterId,
        imageUrl: imageUrl,
        tags: tags,
        updatedAt: DateTime.now(),
      );
      final blog = await blogRemoteDataSource.uploadBlog(blogModel);
      return right(blog);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getAllBlogs({required int page}) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        final blogs = await blogLocalDataSource.loadBlogs();
        return right(blogs);
      }

      final blogs = await blogRemoteDataSource.getAllBlogs(page: page);
      await blogLocalDataSource.uploadLocalBlogs(blogs: blogs);
      return right(blogs);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getBlogsByUser(String userId) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      final blogs = await blogRemoteDataSource.getBlogsByPosterId(userId);
      return right(blogs);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, Blog>> getBlogById(String blogId) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        final cached = await blogLocalDataSource.loadBlogById(blogId);
        if (cached != null) {
          return right(cached);
        }
        return left(Failure('无法连接到网络'));
      }
      final blog = await blogRemoteDataSource.getBlogById(blogId);
      await blogLocalDataSource.uploadLocalBlogs(blogs: [blog]);
      return right(blog);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getBlogsByTag(String tag) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      final blogs = await blogRemoteDataSource.getBlogsByTag(tag);
      return right(blogs);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> searchBlogs(String query) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        final blogs = await blogLocalDataSource.searchLocalBlogs(query);
        return right(blogs);
      }
      final blogs = await blogRemoteDataSource.searchBlogs(query);
      return right(blogs);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteBlog(String blogId) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      final res = await blogRemoteDataSource.deleteBlog(blogId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, Blog>> editBlog({
    required String blogId,
    required String title,
    required String content,
    required List<String> tags,
    required File? image,
    String? imageMimeType,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      // Fetch the current article first: the update addresses the server
      // article id carried on the model, and the existing cover is kept
      // when no new one was picked.
      var blogToUpdate = await blogRemoteDataSource.getBlogById(blogId);
      if (image != null) {
        final newImageUrl = await blogRemoteDataSource.uploadBlogImage(
          image: image,
          mimeType: imageMimeType,
        );
        blogToUpdate = blogToUpdate.copyWith(imageUrl: newImageUrl);
      }
      blogToUpdate = blogToUpdate.copyWith(
        title: title,
        content: content,
        tags: tags,
        updatedAt: DateTime.now(),
      );

      final blogUpdated = await blogRemoteDataSource.editBlog(blogToUpdate);
      return right(blogUpdated);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> toggleLikeBlog(
    String userId,
    String blogId,
  ) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络，收藏未同步'));
      }

      final res = await blogRemoteDataSource.toggleLikeBlog(userId, blogId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error(
        'toggleLikeBlog failed',
        error: e,
        stackTrace: stackTrace,
      );
      return left(Failure('收藏操作失败，请稍后重试'));
    }
  }

  @override
  Future<Either<Failure, bool>> isBlogLiked(
    String userId,
    String blogId,
  ) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure('无法连接到网络'));
      }
      final res = await blogRemoteDataSource.isBlogLikedByUser(userId, blogId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('isBlogLiked failed', error: e, stackTrace: stackTrace);
      return left(Failure('无法获取收藏状态，请稍后重试'));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getUserLikedBlogs(String userId) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure('无法连接到网络'));
      }
      final res = await blogRemoteDataSource.getUserLikedBlogs(userId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error(
        'getUserLikedBlogs failed',
        error: e,
        stackTrace: stackTrace,
      );
      return left(Failure('无法获取收藏列表，请稍后重试'));
    }
  }
}
