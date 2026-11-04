import 'dart:typed_data';

/// A picked image ready to upload: the raw bytes plus the content type.
///
/// Domain and data code must not depend on `dart:io` - the bytes and their
/// MIME type are all an upload needs. Keeping the two together also removes
/// the parallel `image` / `imageMimeType` parameters that used to travel
/// through five layers, where they could drift apart.
class ImageUpload {
  ImageUpload({required this.bytes, String? mimeType})
    : mimeType = mimeType ?? defaultMimeType;

  /// Used when the picker reports no MIME type.
  static const String defaultMimeType = 'image/jpeg';

  final Uint8List bytes;
  final String mimeType;
}
