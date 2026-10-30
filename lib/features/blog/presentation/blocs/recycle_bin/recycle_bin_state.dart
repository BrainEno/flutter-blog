part of 'recycle_bin_bloc.dart';

@immutable
sealed class RecycleBinState {
  const RecycleBinState();
}

final class RecycleBinInitial extends RecycleBinState {}

final class RecycleBinLoading extends RecycleBinState {}

final class RecycleBinSuccess extends RecycleBinState {
  final List<DeletedBlog> blogs;

  /// The tombstone currently being restored, for a per-item spinner; null
  /// when no restore is in flight.
  final String? restoringArticleId;

  /// Title of the tombstone restored by the last transition into this
  /// state, for a one-shot confirmation; null on a plain (re)load.
  final String? lastRestoredTitle;

  const RecycleBinSuccess(
    this.blogs, {
    this.restoringArticleId,
    this.lastRestoredTitle,
  });

  /// Marks the tombstone being restored; restore completion rebuilds the
  /// state outright, so the marker is only ever set, never cleared here.
  RecycleBinSuccess copyWith({String? restoringArticleId}) {
    return RecycleBinSuccess(
      blogs,
      restoringArticleId: restoringArticleId,
      lastRestoredTitle: lastRestoredTitle,
    );
  }
}

/// A restore failed: the list survives (the tombstone is still in the
/// bin) and the failure is surfaced once by the page.
final class RecycleBinRestoreFailure extends RecycleBinState {
  final Failure failure;
  final List<DeletedBlog> blogs;

  const RecycleBinRestoreFailure({required this.failure, required this.blogs});

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get message => failure.message;
}

final class RecycleBinFailure extends RecycleBinState {
  final Failure failure;

  const RecycleBinFailure(this.failure);

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;
}
