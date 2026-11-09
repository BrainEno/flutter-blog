import 'package:belog/features/blog/domain/entities/comment.dart';

/// One page of a comment thread, with replies kept under their root comments.
///
/// The REST response is a plain array. The remote data source builds
/// [nextCursor] from the last top-level comment's exact server timestamp and
/// id. A null cursor means the server returned a short page and the thread is
/// exhausted.
class CommentPage {
  CommentPage({required List<Comment> items, required this.nextCursor})
    : items = List<Comment>.unmodifiable(items);

  /// Root comments in `(createdAt ASC, id ASC)` order.
  final List<Comment> items;

  /// Opaque token to request the next page, or null at the end of the thread.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
