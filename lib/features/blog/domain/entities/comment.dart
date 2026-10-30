/// A comment or a reply on a published article (issue #19).
///
/// Pure Dart domain entity, mirroring [Blog]: free of persistence and UI
/// framework annotations. The server nests replies under their direct
/// parent (up to depth 10); this entity keeps that shape.
class Comment {
  final String id;
  final String articleId;

  /// Stable user id of the comment's author.
  final String authorId;

  /// Direct parent comment id, null for a top-level comment.
  final String? parentCommentId;

  /// Plain-text fallback of the comment body (server content version 0).
  final String content;

  /// Author display fields, resolved from the joined profile; empty when
  /// the profile has no name configured.
  final String authorName;
  final String authorAvatarUrl;

  final DateTime createdAt;
  final List<Comment> replies;

  const Comment({
    required this.id,
    required this.articleId,
    required this.authorId,
    this.parentCommentId,
    required this.content,
    this.authorName = '',
    this.authorAvatarUrl = '',
    required this.createdAt,
    this.replies = const [],
  });

  /// Total number of comments in this subtree, including this one.
  int get totalCount => 1 + replies.fold(0, (sum, r) => sum + r.totalCount);
}
