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
}

/// A restore failed: the list survives (the tombstone is still in the
/// bin) and [message] is surfaced once by the page.
final class RecycleBinRestoreFailure extends RecycleBinState {
  final String message;
  final List<DeletedBlog> blogs;

  const RecycleBinRestoreFailure({required this.message, required this.blogs});
}

final class RecycleBinFailure extends RecycleBinState {
  final String error;

  const RecycleBinFailure(this.error);
}
