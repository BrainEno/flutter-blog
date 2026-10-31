import 'package:belog/features/blog/domain/entities/blog_draft.dart';

/// Local drafts are scoped to an article ID, or null for a new article.
///
/// This port deliberately does not depend on the storage implementation.
abstract interface class BlogDraftStore {
  Future<BlogDraft?> load(String? blogId);

  Future<void> save(BlogDraft draft);

  Future<bool> discardIfUnchanged(BlogDraft draft);

  /// Deletes drafts for [blogId], optionally only through [olderThan].
  /// A successful publish uses the cutoff to preserve edits made while the
  /// upload was in flight.
  Future<int> deleteDraftsFor(String? blogId, {DateTime? olderThan});
}
