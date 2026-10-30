import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';

enum CommentListStatus { initial, loading, loaded, failure }

class CommentState {
  final CommentListStatus status;

  /// Root comments, oldest first; replies are nested.
  final List<Comment> comments;

  /// Display-safe error for the last failed load/submit/delete; empty when
  /// the last action succeeded. This stays Chinese (display-safe) text -
  /// the UI prefers localizing [failure] via `localizedFailure` (issue
  /// #24) and only falls back to this string.
  final String error;

  /// The failure behind [error], when there was one; lets the UI
  /// localize by stable code instead of matching on text.
  final Failure? failure;

  final bool submitting;

  /// Comment ids with an in-flight delete request.
  final Set<String> deletingIds;

  const CommentState({
    this.status = CommentListStatus.initial,
    this.comments = const [],
    this.error = '',
    this.failure,
    this.submitting = false,
    this.deletingIds = const {},
  });

  /// Total comment count including nested replies.
  int get totalCount => comments.fold(0, (sum, c) => sum + c.totalCount);

  /// Copies the state. [error] and [failure] move together: passing
  /// [error] without [failure] clears the stored failure (an empty error
  /// means "no failure"), passing both keeps them in sync, and passing
  /// neither leaves them untouched.
  CommentState copyWith({
    CommentListStatus? status,
    List<Comment>? comments,
    String? error,
    Failure? failure,
    bool? submitting,
    Set<String>? deletingIds,
  }) {
    return CommentState(
      status: status ?? this.status,
      comments: comments ?? this.comments,
      error: error ?? this.error,
      failure: failure ?? (error == null ? this.failure : null),
      submitting: submitting ?? this.submitting,
      deletingIds: deletingIds ?? this.deletingIds,
    );
  }
}
