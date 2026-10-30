import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum CommentListStatus { initial, loading, loaded, failure }

class CommentState {
  final CommentListStatus status;

  /// Root comments, oldest first; replies are nested.
  final List<Comment> comments;

  /// Display-safe error for the last failed load/submit/delete; empty when
  /// the last action succeeded.
  final String error;

  final bool submitting;

  /// Comment ids with an in-flight delete request.
  final Set<String> deletingIds;

  const CommentState({
    this.status = CommentListStatus.initial,
    this.comments = const [],
    this.error = '',
    this.submitting = false,
    this.deletingIds = const {},
  });

  /// Total comment count including nested replies.
  int get totalCount =>
      comments.fold(0, (sum, c) => sum + c.totalCount);

  CommentState copyWith({
    CommentListStatus? status,
    List<Comment>? comments,
    String? error,
    bool? submitting,
    Set<String>? deletingIds,
  }) {
    return CommentState(
      status: status ?? this.status,
      comments: comments ?? this.comments,
      error: error ?? this.error,
      submitting: submitting ?? this.submitting,
      deletingIds: deletingIds ?? this.deletingIds,
    );
  }
}
