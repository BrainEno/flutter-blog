part of 'recycle_bin_bloc.dart';

sealed class RecycleBinEvent {}

final class RecycleBinRequested extends RecycleBinEvent {}

/// Restores the tombstone with the given server article id.
final class RecycleBinRestoreRequested extends RecycleBinEvent {
  final String articleId;

  /// The edition the tombstone is in; null means the content language in
  /// effect. The bin lists one language, but the value is carried explicitly
  /// so a restore can never address a translation the work does not have.
  final String? locale;

  RecycleBinRestoreRequested({required this.articleId, this.locale});
}

/// The active account changed (sign-in, sign-out or a switch).
final class RecycleBinSessionChanged extends RecycleBinEvent {
  /// Whether anybody is signed in after the change; a signed-out bin has
  /// nothing to load.
  final bool hasOwner;

  RecycleBinSessionChanged({required this.hasOwner});
}
