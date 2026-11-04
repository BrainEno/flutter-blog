/// A media asset created by `POST /me/media`.
class NowaveMediaAsset {
  const NowaveMediaAsset({
    required this.id,
    required this.contentType,
    required this.byteSize,
    required this.width,
    required this.height,
  });

  /// Maps the upload response payload.
  ///
  /// The server re-encodes every image to WebP and reports size/dimensions
  /// for the *stored* asset, so a missing field falls back to the WebP
  /// assumption rather than failing the upload. [id] is required: without it
  /// the immutable URL cannot be built.
  factory NowaveMediaAsset.fromDataMap(Map<String, dynamic> map) {
    return NowaveMediaAsset(
      id: map['id'] as String,
      contentType: map['contentType'] as String? ?? 'image/webp',
      byteSize: (map['byteSize'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String contentType;
  final int byteSize;
  final int width;
  final int height;
}
