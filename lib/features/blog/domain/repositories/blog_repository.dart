
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/common/entities/image_upload.dart';

abstract interface class BlogRepository {
  /// [image] is the picked cover; null publishes a text-only article.
  Future<Either<Failure, Blog>> uploadBlog({
    ImageUpload? image,
    required String title,
    required String content,
    required String posterId,
    required List<String> tags,
    NowaveSessionFence? sessionFence,
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

  /// Fetches a 1-based feed page. With no [source], the repository chooses
  /// the network or falls back to the local cache on a connectivity failure.
  /// Pass the first page's source for subsequent pages to avoid mixing
  /// different orderings or cache contents in one scrolling session. Pass
  /// the preceding page's [cursor] only for a pinned network session.
  Future<Either<Failure, BlogFeedPage>> getAllBlogs({
    required int page,
    BlogFeedSource? source,
    String? cursor,
  });

  /// Loads a server-ranked or viewer-specific feed. These lists are online
  /// only: the general article cache cannot reproduce their order or scope.
  Future<Either<Failure, BlogFeedPage>> getOnlineFeed({
    required int page,
    required BlogFeedKind kind,
    String? expectedViewerId,
  });

  Future<Either<Failure, Blog>> getBlogById(String blogId);

  /// Resolves a stored tag name to its server taxonomy; null means the
  /// server has no such tag (an explicit empty state, never "everything").
  Future<Either<Failure, TagRef?>> resolveTag(String name);

  /// One page of a tag's published articles, newest first. The tag listing
  /// is online-only: its order and membership are the server's.
  Future<Either<Failure, List<Blog>>> getArticlesByTag(
    String slug, {
    required int offset,
  });

  Future<Either<Failure, List<Blog>>> searchBlogs(String query);

  Future<Either<Failure, List<Blog>>> getBlogsByUser(String userId);

  /// The viewer's own articles, including server-side drafts, newest update
  /// first. Online only and never cached: the local cache mirrors the public
  /// feed, where a draft must not appear. The read is scoped to [userId].
  Future<Either<Failure, List<Blog>>> getMyArticles({required String userId});

  Future<Either<Failure, Blog>> editBlog({
    required String blogId,
    required String title,
    required String content,
    required List<String> tags,
    ImageUpload? image,
    NowaveSessionFence? sessionFence,
  });

  Future<Either<Failure, bool>> toggleLikeBlog(String userId, String blogId);

  Future<Either<Failure, bool>> isBlogLiked(String userId, String blogId);

  Future<Either<Failure, List<Blog>>> getUserLikedBlogs(String userId);

  /// Articles the server recommends next to [blogId] (slug). Related
  /// articles are a best-effort rider: failures can safely hide the
  /// section without breaking the viewer.
  Future<Either<Failure, List<Blog>>> getRelatedArticles(String blogId);
}
