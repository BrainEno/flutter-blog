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

  /// True while the next page of older comments is loading.
  final bool isLoadingMore;

  /// Whether another root-comment cursor request can be made.
  final bool hasMore;

  /// Retryable failure from loading an older page; loaded comments stay visible.
  final Failure? loadMoreFailure;

  /// The deployment rejected or ignored the cursor, so continuation stopped.
  final bool paginationUnavailable;

  const CommentState({
    this.status = CommentListStatus.initial,
    this.comments = const [],
    this.error = '',
    this.failure,
    this.submitting = false,
    this.deletingIds = const {},
    this.isLoadingMore = false,
    this.hasMore = false,
    this.loadMoreFailure,
    this.paginationUnavailable = false,
  });

  /// Count of currently loaded comments, including nested replies.
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
    bool? isLoadingMore,
    bool? hasMore,
    Failure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
    bool? paginationUnavailable,
  }) {
    return CommentState(
      status: status ?? this.status,
      comments: comments ?? this.comments,
      error: error ?? this.error,
      failure: failure ?? (error == null ? this.failure : null),
      submitting: submitting ?? this.submitting,
      deletingIds: deletingIds ?? this.deletingIds,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      loadMoreFailure: clearLoadMoreFailure
          ? null
          : (loadMoreFailure ?? this.loadMoreFailure),
      paginationUnavailable:
          paginationUnavailable ?? this.paginationUnavailable,
    );
  }
}
