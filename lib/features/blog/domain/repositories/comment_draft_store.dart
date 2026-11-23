/// A comment written under an article but not sent yet.
class CommentDraft {
  const CommentDraft({
    required this.text,
    this.parentCommentId,
    this.parentAuthorName = '',
  });

  /// What the reader typed, exactly as typed.
  final String text;

  /// The comment it answers; null for a top-level comment.
  final String? parentCommentId;

  /// The display name of the answered comment's author, so the "replying
  /// to" line can be shown again before (or without) that comment loading.
  final String parentAuthorName;

  /// Whether there is anything worth keeping.
  bool get isBlank => text.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is CommentDraft &&
      other.text == text &&
      other.parentCommentId == parentCommentId &&
      other.parentAuthorName == parentAuthorName;

  @override
  int get hashCode => Object.hash(text, parentCommentId, parentAuthorName);
}

/// Where unsent comments wait until they are sent or thrown away.
///
/// A draft belongs to one signed-in account on one backend and one article,
/// like the reading history, and never leaves the device. Each account keeps
/// a bounded number of drafts; writing one makes it the newest.
abstract interface class CommentDraftStore {
  /// [userId]'s unsent comment under the article [slug], or null.
  Future<CommentDraft?> load({required String userId, required String slug});

  /// Keeps [draft] as [userId]'s unsent comment under [slug]; a blank draft
  /// removes it instead.
  Future<void> save({
    required String userId,
    required String slug,
    required CommentDraft draft,
  });
}
