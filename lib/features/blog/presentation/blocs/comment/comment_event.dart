import 'package:equatable/equatable.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';

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
  final NowaveSessionFence? fence;

  const CommentSubmitted({
    required this.content,
    this.parentCommentId,
    this.fence,
  });

  @override
  List<Object?> get props => [
    content,
    parentCommentId,
    fence?.userId,
    fence?.generation,
  ];
}

/// Deletes one of the viewer's own comments (replies cascade).
final class CommentDeleteRequested extends CommentEvent {
  final String commentId;
  final NowaveSessionFence? fence;

  const CommentDeleteRequested(this.commentId, {this.fence});

  @override
  List<Object?> get props => [commentId, fence?.userId, fence?.generation];
}

/// Internal synchronization event; the identity stream is fenced immediately
/// before this event is delivered to the state machine.
final class CommentIdentityChanged extends CommentEvent {
  const CommentIdentityChanged(this.epoch);
  final int epoch;
  @override
  List<Object?> get props => [epoch];
}
