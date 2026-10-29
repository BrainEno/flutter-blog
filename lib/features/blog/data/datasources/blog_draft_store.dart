import 'package:belog/features/blog/domain/entities/blog_draft.dart';

/// Local drafts are scoped to an article ID, or null for a new article.
///
/// Implementations live in the data layer (currently [SqliteBlogDraftStore]
/// backed by Drift/SQLite).
abstract interface class BlogDraftStore {
  Future<BlogDraft?> load(String? blogId);

  Future<void> save(BlogDraft draft);

  Future<bool> discardIfUnchanged(BlogDraft draft);

  /// Deletes every draft scoped to [blogId].
  ///
  /// When [olderThan] is given, only drafts updated at or before that moment
  /// are removed: used after a successful publish so edits made while the
  /// upload was in flight survive as a draft, while the published snapshot
  /// itself is not resurrected next time the editor opens.
  Future<int> deleteDraftsFor(String? blogId, {DateTime? olderThan});
}
