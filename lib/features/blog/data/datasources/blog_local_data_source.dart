import 'package:belog/features/blog/data/models/blog_model.dart';

/// Offline cache of published articles.
///
/// Implementations live in the data layer (currently
/// [SqliteBlogCache] backed by Drift/SQLite). Writes must be awaited and rows
/// are identified by the remote business id, never by a local auto-increment
/// key.
abstract interface class BlogLocalDataSource {
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs});

  /// Reads cached articles in deterministic update-time/id order. [limit]
  /// is bounded to 500 and [offset] is zero-based; both apply in SQLite,
  /// before article bodies are decoded.
  Future<List<BlogModel>> loadBlogs({int limit = 500, int offset = 0});

  Future<List<BlogModel>> searchLocalBlogs(String query);

  /// Returns the cached article with the given business id, if present.
  Future<BlogModel?> loadBlogById(String id);

  /// Drops the cached article with the given business id (the server copy
  /// was deleted, so the cached row must not outlive it offline).
  Future<void> deleteCachedBlog(String id);
}
