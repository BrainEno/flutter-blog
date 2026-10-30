import 'package:equatable/equatable.dart';

sealed class CommentEvent extends Equatable {
  const CommentEvent();

  @override
  List<Object?> get props => [];
}

/// (Re)loads the whole comment thread of the bloc's article.
final class CommentsRequested extends CommentEvent {
  const CommentsRequested();
}

/// Submits the composer's text as a new comment, or as a reply when
/// [parentCommentId] points at an existing comment.
final class CommentSubmitted extends CommentEvent {
  final String content;
  final String? parentCommentId;

  const CommentSubmitted({required this.content, this.parentCommentId});

  @override
  List<Object?> get props => [content, parentCommentId];
}

/// Deletes one of the viewer's own comments (replies cascade).
final class CommentDeleteRequested extends CommentEvent {
  final String commentId;

  const CommentDeleteRequested(this.commentId);

  @override
  List<Object?> get props => [commentId];
}
