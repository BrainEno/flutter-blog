import 'package:equatable/equatable.dart';

sealed class CommentEvent extends Equatable {
  const CommentEvent();

  @override
  List<Object?> get props => [];
}

/// Loads or resets the first page of the bloc's article thread.
final class CommentsRequested extends CommentEvent {
  const CommentsRequested();
}

/// Loads the next page of top-level comments for the current article.
final class MoreCommentsRequested extends CommentEvent {
  const MoreCommentsRequested();
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
