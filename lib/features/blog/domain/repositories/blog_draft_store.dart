import 'package:belog/features/blog/domain/entities/blog_draft.dart';

/// Local drafts are scoped to an account and an article ID, or null for a
/// new article. Implementations must also separate different API backends.
/// This port deliberately does not depend on the storage implementation.
abstract interface class BlogDraftStore {
  Future<BlogDraft?> load(String? blogId, {required String userId});

  Future<void> save(BlogDraft draft);

  /// Delete only the exact snapshot (scope, id, timestamp and content). Used
  /// for recovery choices and for best-effort post-publish cleanup.
  Future<bool> discardIfUnchanged(BlogDraft draft);

  /// Whether pre-account-scoping drafts exist. Their ownership is unknown;
  /// this does not grant access to their content or assign them to an account.
  Future<bool> hasUnclaimedDrafts();

  /// Deletes only this account's drafts for [blogId], optionally strictly
  /// before [olderThan]. Timestamp cutoffs alone cannot prove a row has not
  /// changed; publish cleanup uses [discardIfUnchanged] instead.
  Future<int> deleteDraftsFor(
    String? blogId, {
    required String userId,
    DateTime? olderThan,
  });
}
