import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_feed_loader.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/common/entities/image_upload.dart';

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
  Future<Either<Failure, String>> uploadCover({
    required ImageUpload image,
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      return right(await _uploadCoverBytes(image, sessionFence));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, Blog>> uploadBlog({
    ImageUpload? image,
    String? uploadedCoverUrl,
    required String title,
    required String content,
    required String posterId,
    required List<String> tags,
    NowaveSessionFence? sessionFence,
    String? idempotencyKey,
    List<String>? categoryIds,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // Media assets are immutable and addressed by their own id, so the
      // cover is uploaded first and the article row is created with it.
      // A failure between the two only leaves an unreferenced asset (the
      // backend has no delete endpoint; its lifecycle is managed
      // server-side) - which is exactly why a caller that already uploaded the
      // cover passes [uploadedCoverUrl] instead of making a second asset.
      // A coverless publish (issue #17) skips the upload.
      final imageUrl =
          uploadedCoverUrl ?? await _uploadCoverBytes(image, sessionFence);
      final blogModel = BlogModel(
        id: '',
        title: title,
        content: content,
        posterId: posterId,
        imageUrl: imageUrl,
        tags: tags,
        updatedAt: DateTime.now(),
      );
      final blog = sessionFence == null
          ? await blogRemoteDataSource.uploadBlog(
              blogModel,
              idempotencyKey: idempotencyKey,
              categoryIds: categoryIds,
            )
          : await blogRemoteDataSource.uploadBlog(
              blogModel,
              sessionFence: sessionFence,
              idempotencyKey: idempotencyKey,
              categoryIds: categoryIds,
            );
      return right(blog);
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  /// Uploads [image] and returns the URL the server stored it at.
  ///
  /// A null [image] is a coverless publish and uploads nothing. No failure
  /// mapping happens here: the callers wrap it, so an upload error surfaces
  /// through the same path as the rest of their work.
  Future<String> _uploadCoverBytes(
    ImageUpload? image,
    NowaveSessionFence? sessionFence,
  ) async {
    if (image == null) return '';
    if (sessionFence == null) {
      return blogRemoteDataSource.uploadBlogImage(image: image);
    }
    return blogRemoteDataSource.uploadBlogImage(
      image: image,
      sessionFence: sessionFence,
    );
  }

  @override
  Future<Either<Failure, BlogFeedPage>> getAllBlogs({
    required int page,
    BlogFeedSource? source,
    String? cursor,
  }) {
    return BlogFeedLoader(
      blogRemoteDataSource,
      blogLocalDataSource,
      connectionChecker,
    ).load(page: page, source: source, cursor: cursor);
  }

  @override
  Future<Either<Failure, BlogFeedPage>> getOnlineFeed({
    required int page,
    required BlogFeedKind kind,
    String? expectedViewerId,
  }) {
    return BlogFeedLoader(
      blogRemoteDataSource,
      blogLocalDataSource,
      connectionChecker,
    ).loadOnline(page: page, kind: kind, expectedViewerId: expectedViewerId);
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
  Future<Either<Failure, List<Blog>>> getMyArticles({
    required String userId,
  }) async {
    if (userId.isEmpty) return left(Failure.auth('请先登录账户'));
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // Deliberately not cached and not retried: a draft is private, and an
      // automatic retry after a transport error could show one account's
      // list to another.
      final blogs = await blogRemoteDataSource.getMyArticles(userId: userId);
      return right(blogs);
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, ArticleEditions>> getMyArticleEditions({
    required String userId,
  }) async {
    if (userId.isEmpty) return left(Failure.auth('请先登录账户'));
    try {
      // Cross-language reads are account-scoped too, and an offline fallback
      // would answer from the public cache while claiming to be the author's
      // own list.
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      return right(
        await blogRemoteDataSource.getMyArticleEditions(userId: userId),
      );
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
  Future<Either<Failure, TagRef?>> resolveTag(String name) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(await blogRemoteDataSource.resolveTag(name));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getArticlesByTag(
    String slug, {
    required int offset,
  }) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(
        await blogRemoteDataSource.getArticlesByTag(slug, offset: offset),
      );
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
  Future<Either<Failure, Blog>> restoreDeletedBlog(
    String articleId, {
    String? locale,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // Name the edition when it is known; an unknown one leaves the argument
      // off so the data source's default (content language) applies.
      final edition = (locale ?? '').trim();
      return right(
        edition.isEmpty
            ? await blogRemoteDataSource.restoreArticle(articleId)
            : await blogRemoteDataSource.restoreArticle(
                articleId,
                locale: edition,
              ),
      );
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
    ImageUpload? image,
    String? uploadedCoverUrl,
    String? locale,
    NowaveSessionFence? sessionFence,
    List<String>? categoryIds,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // Fetch the current article first: the update addresses the server
      // article id carried on the model, and the existing cover is kept
      // when no new one was picked.
      // Read the edition being edited, not whichever translation the current
      // content language resolves to: the write below replaces exactly the
      // translation named in its body. An unknown edition leaves the argument
      // off, so the data source's own default applies.
      final edition = (locale ?? '').trim();
      var blogToUpdate = edition.isEmpty
          ? (sessionFence == null
                ? await blogRemoteDataSource.getBlogById(blogId)
                : await blogRemoteDataSource.getBlogById(
                    blogId,
                    sessionFence: sessionFence,
                  ))
          : (sessionFence == null
                ? await blogRemoteDataSource.getBlogById(
                    blogId,
                    locale: edition,
                  )
                : await blogRemoteDataSource.getBlogById(
                    blogId,
                    sessionFence: sessionFence,
                    locale: edition,
                  ));
      if (!blogToUpdate.plainEditorCompatible ||
          blogToUpdate.serverSummary == null) {
        // Reject before uploading a cover or mutating anything: flattening a
        // richer server document into v0 paragraphs would overwrite content.
        return left(
          const Failure(
            '无法安全保留这篇文章的正文或摘要，请在 no-wave 网页编辑',
            kind: FailureKind.validation,
            code: 'article.structuredEditUnsupported',
          ),
        );
      }
      // An empty URL means "no new cover": the fetched article keeps its own.
      final coverUrl =
          uploadedCoverUrl ?? await _uploadCoverBytes(image, sessionFence);
      if (coverUrl.isNotEmpty) {
        blogToUpdate = blogToUpdate.copyWith(imageUrl: coverUrl);
      }
      blogToUpdate = blogToUpdate.copyWith(
        title: title,
        content: content,
        tags: tags,
        updatedAt: DateTime.now(),
      );

      final blogUpdated = sessionFence == null
          ? await blogRemoteDataSource.editBlog(
              blogToUpdate,
              categoryIds: categoryIds,
            )
          : await blogRemoteDataSource.editBlog(
              blogToUpdate,
              sessionFence: sessionFence,
              categoryIds: categoryIds,
            );
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
