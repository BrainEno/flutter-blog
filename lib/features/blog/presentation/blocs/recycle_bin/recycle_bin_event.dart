part of 'recycle_bin_bloc.dart';

sealed class RecycleBinEvent {}

final class RecycleBinRequested extends RecycleBinEvent {}

/// Restores the tombstone with the given server article id.
final class RecycleBinRestoreRequested extends RecycleBinEvent {
  final String articleId;

  RecycleBinRestoreRequested({required this.articleId});
}
