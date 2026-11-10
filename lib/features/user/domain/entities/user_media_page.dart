import 'package:belog/features/user/domain/entities/user_media_asset.dart';

/// One cursor page from the authenticated media library.
class UserMediaPage {
  UserMediaPage({required List<UserMediaAsset> items, required this.nextCursor})
    : items = List.unmodifiable(items);

  final List<UserMediaAsset> items;

  /// Opaque server cursor for the next page, or null when the list is complete.
  final String? nextCursor;
}
