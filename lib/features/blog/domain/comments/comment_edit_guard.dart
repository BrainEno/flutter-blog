import 'package:belog/features/blog/domain/entities/comment.dart';

/// Pure operations on the currently loaded comment tree. These checks are
/// local reconciliation only: they cannot replace the server-side revision
/// precondition that the comment PATCH API does not yet offer.
class CommentEditGuard {
  const CommentEditGuard._();

  /// The API currently issues UUIDs but documents identifiers as opaque.
  /// Restrict client writes to one conservative URL segment rather than
  /// interpreting an untrusted server value as a path or query. A future
  /// issuer using other characters needs explicit path-segment support.
  static bool isSafeId(String value) {
    if (value.isEmpty || value.length > 300) return false;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
  }

  /// Do not open a text editor if the response cannot establish the original
  /// identity or if the editor's smaller input cap would truncate its body.
  /// A legacy or malformed timestamp is not a trustworthy edit snapshot.
  static bool canEdit(Comment comment, {required int maxLength}) {
    if (!comment.isPlainText || !isSafeId(comment.id)) return false;
    if (comment.articleId.isEmpty || comment.authorId.isEmpty) return false;
    if (comment.content.trim().isEmpty || comment.content.length > maxLength) {
      return false;
    }
    if (comment.createdAt.millisecondsSinceEpoch <= 0) return false;
    return true;
  }

  /// Find a loaded node, including legacy reply trees deeper than the current
  /// server write limit. Unknown/unloaded comments are never editable here.
  static Comment? find(List<Comment> roots, String id) {
    for (final node in roots) {
      if (node.id == id) return node;
      final found = find(node.replies, id);
      if (found != null) return found;
    }
    return null;
  }

  /// The snapshot includes ownership, tree position, text and edit marker.
  /// Replies are deliberately excluded: new replies should not prevent the
  /// author from correcting the parent, nor be replaced by a stale response.
  static bool sameSnapshot(Comment current, Comment original) {
    return current.id == original.id &&
        current.articleId == original.articleId &&
        current.authorId == original.authorId &&
        current.parentCommentId == original.parentCommentId &&
        current.content == original.content &&
        current.createdAt == original.createdAt &&
        current.editedAt == original.editedAt &&
        current.isPlainText &&
        original.isPlainText;
  }

  /// An untrusted response cannot move a comment, change its author, flatten
  /// an unexpected document, or replace the user's submitted text.
  static bool acceptsResponse(
    Comment original,
    Comment updated,
    String content,
  ) {
    return updated.id == original.id &&
        updated.articleId == original.articleId &&
        updated.authorId == original.authorId &&
        updated.parentCommentId == original.parentCommentId &&
        updated.createdAt == original.createdAt &&
        updated.isPlainText &&
        updated.editedAt != null &&
        updated.content == content;
  }

  /// Replace just the body and edit timestamp, preserving the tree that is
  /// actually visible, including any replies received during the request.
  /// If the node is gone or changed locally, the original list is returned.
  static List<Comment> apply(
    List<Comment> roots,
    Comment original,
    Comment updated,
  ) {
    final current = find(roots, original.id);
    if (current == null || !sameSnapshot(current, original)) return roots;
    return _replace(roots, original.id, updated);
  }

  static List<Comment> _replace(
    List<Comment> nodes,
    String id,
    Comment updated,
  ) {
    return [
      for (final node in nodes)
        if (node.id == id)
          Comment(
            id: node.id,
            articleId: node.articleId,
            authorId: node.authorId,
            parentCommentId: node.parentCommentId,
            content: updated.content,
            isPlainText: updated.isPlainText,
            authorName: updated.authorName,
            authorAvatarUrl: updated.authorAvatarUrl,
            createdAt: node.createdAt,
            editedAt: updated.editedAt,
            replies: node.replies,
          )
        else
          _withReplies(node, _replace(node.replies, id, updated)),
    ];
  }

  static Comment _withReplies(Comment node, List<Comment> replies) => Comment(
    id: node.id,
    articleId: node.articleId,
    authorId: node.authorId,
    parentCommentId: node.parentCommentId,
    content: node.content,
    isPlainText: node.isPlainText,
    authorName: node.authorName,
    authorAvatarUrl: node.authorAvatarUrl,
    createdAt: node.createdAt,
    editedAt: node.editedAt,
    replies: replies,
  );
}
