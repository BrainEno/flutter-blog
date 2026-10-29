import 'package:belog/features/blog/data/models/blog_model.dart';

/// Offline cache of published articles.
///
/// Implementations live in the data layer (currently
/// [SqliteBlogCache] backed by Drift/SQLite). Writes must be awaited and rows
/// are identified by the remote business id, never by a local auto-increment
/// key.
abstract interface class BlogLocalDataSource {
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs});

  Future<List<BlogModel>> loadBlogs();

  Future<List<BlogModel>> searchLocalBlogs(String query);

  /// Returns the cached article with the given business id, if present.
  Future<BlogModel?> loadBlogById(String id);
}
