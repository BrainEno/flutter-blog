import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/latest_feed_cursor.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:fpdart/fpdart.dart';

/// Loads the article feeds and decides when a cached list may stand in for a
/// network one.
///
/// Kept out of the repository because the rules are about paging sessions, not
/// about persistence: every page of a scrolling session stays on the first
/// page's source, a cursor session never silently falls back to offsets, and
/// only a new unpinned feed may degrade to the cache.
class BlogFeedLoader {
  const BlogFeedLoader(this._remote, this._local, this._connectionChecker);

  final BlogRemoteDataSource _remote;
  final BlogLocalDataSource _local;
  final ConnectionChecker _connectionChecker;

  Future<Either<Failure, BlogFeedPage>> load({
    required int page,
    BlogFeedSource? source,
    String? cursor,
  }) async {
    if (page < 1) return left(Failure.validation('页码必须大于零'));
    if (cursor != null && (page < 2 || source != BlogFeedSource.network)) {
      return left(Failure.validation('无效的文章分页请求'));
    }

    // Keep every page in a scrolling session on the first page's source.
    // In particular, reconnecting must not splice a remote page into a
    // (potentially incomplete and differently ordered) cached list.
    if (source == BlogFeedSource.cache) return _loadCachedFeed(page);

    late List<BlogModel> blogs;
    String? nextCursor;
    try {
      if (!await _connectionChecker.isConnected) {
        if (source == BlogFeedSource.network) {
          return left(Failure.networkOffline());
        }
        return await _loadCachedFeed(page);
      }
      if (cursor == null) {
        blogs = await _remote.getAllBlogs(page: page);
        // Once a session has fallen back to offsets, do not re-enable cursor
        // halfway through its differently positioned list.
        if (page == 1) {
          nextCursor = LatestFeedContinuation.tryStart(blogs)?.token;
        }
      } else {
        try {
          final slice = await _remote.getAllBlogsAfter(cursor: cursor);
          blogs = slice.blogs;
          nextCursor = slice.nextCursor;
        } on LatestFeedCursorUnavailable {
          if (page != 2) {
            return left(
              const Failure('文章分页方式已改变，请刷新后重试', code: 'feed.paginationChanged'),
            );
          }
          // Older servers may ignore the query parameter or reject it. This
          // is the first continuation, so use legacy offsets for this session.
          blogs = await _remote.getAllBlogs(page: page);
        } on LatestFeedCursorTooDense {
          return left(
            const Failure(
              '同一毫秒内的文章过多，无法安全继续分页；请刷新后重试',
              code: 'feed.paginationDense',
            ),
          );
        }
      }
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
      await _local.uploadLocalBlogs(blogs: blogs);
    } catch (error) {
      return left(Failure.storage(cause: error));
    }
    return right(
      BlogFeedPage(
        blogs: blogs,
        source: BlogFeedSource.network,
        nextCursor: nextCursor,
      ),
    );
  }

  Future<Either<Failure, BlogFeedPage>> loadOnline({
    required int page,
    required BlogFeedKind kind,
    String? expectedViewerId,
  }) async {
    if (page < 1 || kind == BlogFeedKind.latest) {
      return left(Failure.validation('无效的文章列表请求'));
    }
    if (kind == BlogFeedKind.following &&
        (expectedViewerId == null || expectedViewerId.isEmpty)) {
      return left(Failure.auth('请先登录账户'));
    }
    try {
      if (!await _connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      final blogs = await _remote.getOnlineFeed(
        page: page,
        kind: kind,
        expectedViewerId: expectedViewerId,
      );
      // Never use or write the general cache for these lists. It cannot
      // represent editorial order, popularity or an account's follow graph.
      return right(BlogFeedPage(blogs: blogs, source: BlogFeedSource.network));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  Future<Either<Failure, BlogFeedPage>> _loadCachedFeed(int page) async {
    try {
      final blogs = await _local.loadBlogs(
        limit: kBlogPageSize,
        offset: (page - 1) * kBlogPageSize,
      );
      return right(BlogFeedPage(blogs: blogs, source: BlogFeedSource.cache));
    } catch (error) {
      return left(Failure.storage(cause: error));
    }
  }
}
