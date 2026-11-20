import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';

/// Offline cache of published articles.
///
/// Implementations live in the data layer (currently
/// [SqliteBlogCache] backed by Drift/SQLite). Writes must be awaited and rows
/// are identified by the remote business id, never by a local auto-increment
/// key.
///
/// Rows are scoped by content language (#108): reads only see the language the
/// implementation was built for, so a language switch has its own (initially
/// empty) cache instead of serving another language's articles. Deletes remove
/// the article in every language, because the server copy is gone.
abstract interface class BlogLocalDataSource {
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs});

  /// Reads cached articles in deterministic update-time/id order. [limit]
  /// is bounded to 500 and [offset] is zero-based; both apply in SQLite,
  /// before article bodies are decoded.
  Future<List<BlogModel>> loadBlogs({
    int limit = AppLimits.blogCacheMaxRows,
    int offset = 0,
  });

  Future<List<BlogModel>> searchLocalBlogs(String query);

  /// Returns a local-only catalog for this datasource's exact backend and
  /// content-language namespace. It does not update LRU timestamps: browsing
  /// cache metadata is not the same thing as opening an article.
  Future<OfflineLibrarySnapshot> inspectOfflineLibrary();

  /// Removes only the public cached articles in this datasource's current
  /// backend/content-language namespace. It never clears drafts, queues,
  /// session data, reading history, another backend, or another language.
  Future<void> clearOfflineLibrary();

  /// Returns the cached article with the given business id, if present.
  Future<BlogModel?> loadBlogById(String id);

  /// Drops the cached article with the given business id (the server copy
  /// was deleted, so the cached row must not outlive it offline).
  Future<void> deleteCachedBlog(String id);
}
