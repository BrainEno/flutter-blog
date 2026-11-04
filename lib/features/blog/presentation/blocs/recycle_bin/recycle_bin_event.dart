part of 'recycle_bin_bloc.dart';

sealed class RecycleBinEvent {}

final class RecycleBinRequested extends RecycleBinEvent {}

/// Restores the tombstone with the given server article id.
final class RecycleBinRestoreRequested extends RecycleBinEvent {
  final String articleId;

  RecycleBinRestoreRequested({required this.articleId});
}

/// The active account changed (sign-in, sign-out or a switch).
final class RecycleBinSessionChanged extends RecycleBinEvent {
  /// Whether anybody is signed in after the change; a signed-out bin has
  /// nothing to load.
  final bool hasOwner;

  RecycleBinSessionChanged({required this.hasOwner});
}
