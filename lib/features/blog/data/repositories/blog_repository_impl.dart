import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
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
    File? image,
    required String title,
    required String content,
    required String posterId,
    required List<String> tags,
    String? imageMimeType,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // Media assets are immutable and addressed by their own id, so the
      // cover is uploaded first and the article row is created with it.
      // A failure between the two only leaves an unreferenced asset (the
      // backend has no delete endpoint; its lifecycle is managed
      // server-side). A coverless publish (issue #17) skips the upload.
      final imageUrl = image == null
          ? ''
          : await blogRemoteDataSource.uploadBlogImage(
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
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, BlogFeedPage>> getAllBlogs({
    required int page,
    BlogFeedSource? source,
  }) async {
    if (page < 1) return left(Failure.validation('页码必须大于零'));

    // Keep every page in a scrolling session on the first page's source.
    // In particular, reconnecting must not splice a remote offset into a
    // (potentially incomplete and differently ordered) cached list.
    if (source == BlogFeedSource.cache) return _loadCachedFeed(page);

    late final List<BlogModel> blogs;
    try {
      if (!await connectionChecker.isConnected) {
        if (source == BlogFeedSource.network) {
          return left(Failure.networkOffline());
        }
        return await _loadCachedFeed(page);
      }
      blogs = await blogRemoteDataSource.getAllBlogs(page: page);
    } catch (error) {
      final failure = mapErrorToFailure(error);
      // A connection probe can succeed just before a socket fails. Only a
      // new, unpinned feed may fall back; auth/permission/server errors and
      // later pages must not silently turn into a cached success.
      if (source == null &&
          (failure.kind == FailureKind.network ||
              failure.kind == FailureKind.timeout)) {
        return _loadCachedFeed(page);
      }
      return left(failure);
    }

    try {
      await blogLocalDataSource.uploadLocalBlogs(blogs: blogs);
    } catch (error) {
      return left(Failure.storage(cause: error));
    }
    return right(BlogFeedPage(blogs: blogs, source: BlogFeedSource.network));
  }

  Future<Either<Failure, BlogFeedPage>> _loadCachedFeed(int page) async {
    try {
      final blogs = await blogLocalDataSource.loadBlogs(
        limit: kBlogPageSize,
        offset: (page - 1) * kBlogPageSize,
      );
      return right(BlogFeedPage(blogs: blogs, source: BlogFeedSource.cache));
    } catch (error) {
      return left(Failure.storage(cause: error));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getBlogsByUser(String userId) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      final blogs = await blogRemoteDataSource.getBlogsByPosterId(userId);
      return right(blogs);
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, Blog>> getBlogById(String blogId) async {
    try {
      if (!await connectionChecker.isConnected) {
        try {
          final cached = await blogLocalDataSource.loadBlogById(blogId);
          return cached == null
              ? left(Failure.networkOffline())
              : right(cached);
        } catch (error) {
          return left(Failure.storage(cause: error));
        }
      }
      final blog = await blogRemoteDataSource.getBlogById(blogId);
      try {
        await blogLocalDataSource.uploadLocalBlogs(blogs: [blog]);
      } catch (error) {
        return left(Failure.storage(cause: error));
      }
      return right(blog);
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getBlogsByTag(String tag) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      final blogs = await blogRemoteDataSource.getBlogsByTag(tag);
      return right(blogs);
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> searchBlogs(String query) async {
    try {
      if (!await connectionChecker.isConnected) {
        try {
          return right(await blogLocalDataSource.searchLocalBlogs(query));
        } catch (error) {
          return left(Failure.storage(cause: error));
        }
      }
      return right(await blogRemoteDataSource.searchBlogs(query));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, bool>> deleteBlog(String blogId) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // The delete endpoint addresses the server UUID, the app addresses
      // articles by slug: resolve via the cache first (no extra request),
      // falling back to a remote fetch like editBlog does.
      late String articleId;
      try {
        articleId =
            (await blogLocalDataSource.loadBlogById(blogId))?.articleId ?? '';
      } catch (error) {
        return left(Failure.storage(cause: error));
      }
      if (articleId.isEmpty) {
        articleId = (await blogRemoteDataSource.getBlogById(blogId)).articleId;
      }
      final res = await blogRemoteDataSource.deleteArticle(articleId);
      if (res) {
        try {
          await blogLocalDataSource.deleteCachedBlog(blogId);
        } catch (error) {
          // Do not report an ordinary delete failure: the server already
          // committed. The cached row may still be visible while offline.
          return left(
            Failure(
              '文章已在服务器删除，但本地缓存未清除；离线时可能仍显示旧内容',
              kind: FailureKind.storage,
              code: 'article.deletedCacheFailed',
              cause: error,
            ),
          );
        }
      }
      return right(res);
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, List<DeletedBlog>>> getDeletedBlogs() async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      return right(await blogRemoteDataSource.getDeletedBlogs());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, Blog>> restoreDeletedBlog(String articleId) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      return right(await blogRemoteDataSource.restoreArticle(articleId));
    } catch (error) {
      return left(mapErrorToFailure(error));
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
        return left(Failure.networkOffline());
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
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, bool>> toggleLikeBlog(
    String userId,
    String blogId,
  ) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(
          Failure(
            '无法连接到网络，收藏未同步',
            kind: FailureKind.network,
            code: 'network.offline',
            l10nKey: 'likes.sync',
          ),
        );
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
      return left(Failure('收藏操作失败，请稍后重试', code: 'likes.toggle'));
    }
  }

  @override
  Future<Either<Failure, bool>> isBlogLiked(
    String userId,
    String blogId,
  ) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      final res = await blogRemoteDataSource.isBlogLikedByUser(userId, blogId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('isBlogLiked failed', error: e, stackTrace: stackTrace);
      return left(Failure('无法获取收藏状态，请稍后重试', code: 'likes.status'));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getRelatedArticles(String blogId) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      final res = await blogRemoteDataSource.getRelatedArticles(blogId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error(
        'getRelatedArticles failed',
        error: e,
        stackTrace: stackTrace,
      );
      return left(Failure('无法获取相关文章', code: 'related.load'));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getUserLikedBlogs(String userId) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
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
      return left(Failure('无法获取收藏列表，请稍后重试', code: 'likes.list'));
    }
  }
}
