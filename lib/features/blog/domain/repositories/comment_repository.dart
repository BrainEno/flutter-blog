import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:fpdart/fpdart.dart';

/// The server rejected a continuation, so this deployment cannot page comments.
const commentCursorUnavailableFailureCode = 'comments.cursorUnavailable';

/// Comment lifecycle on a published article (issue #19).
abstract interface class CommentRepository {
  /// Reads a page of root comments in `(createdAt ASC, id ASC)` order.
  /// Replies remain nested under their root; [cursor] continues after the last
  /// root of the previous page. A short page has no next cursor.
  Future<Either<Failure, CommentPage>> getComments(
    String slug, {
    String? cursor,
  });

  /// Posts a plain-text comment (or a reply when [parentCommentId] is set).
  ///
  /// [idempotencyKey] is forwarded as the server's `Idempotency-Key`
  /// header: a retried submit with the same key replays the original
  /// comment instead of duplicating it.
  Future<Either<Failure, Comment>> createComment({
    required String slug,
    required String content,
    String? parentCommentId,
    required String idempotencyKey,
  });

  /// Deletes one of the viewer's own comments; the server cascades to the
  /// comment's whole reply subtree.
  Future<Either<Failure, void>> deleteComment(String commentId);
}
