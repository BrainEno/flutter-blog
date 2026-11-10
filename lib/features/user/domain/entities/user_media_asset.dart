/// A normalized image already stored in this account's no-wave media library.
///
/// [imageUrl] is built from the asset id by the client, not trusted from the
/// API's `src` field: older API versions return that field without `/v1`.
class UserMediaAsset {
  const UserMediaAsset({
    required this.id,
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.createdAt,
  });

  final String id;
  final String imageUrl;
  final int width;
  final int height;
  final int byteSize;
  final DateTime createdAt;
}
