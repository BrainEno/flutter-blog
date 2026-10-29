import 'package:belog/features/blog/domain/entities/blog_draft.dart';

/// Local drafts are scoped to an article ID, or null for a new article.
///
/// Implementations live in the data layer (currently [SqliteBlogDraftStore]
/// backed by Drift/SQLite).
abstract interface class BlogDraftStore {
  Future<BlogDraft?> load(String? blogId);

  Future<void> save(BlogDraft draft);

  Future<bool> discardIfUnchanged(BlogDraft draft);
}
