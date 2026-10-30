import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:fpdart/fpdart.dart';

/// Comment lifecycle on a published article (issue #19).
abstract interface class CommentRepository {
  /// Whole thread tree for [slug], oldest first, replies nested.
  Future<Either<Failure, List<Comment>>> getComments(String slug);

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
