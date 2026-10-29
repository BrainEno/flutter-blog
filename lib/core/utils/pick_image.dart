import 'dart:io';

import 'package:belog/core/utils/app_logger.dart';
import 'package:image_picker/image_picker.dart';

/// A picked, already-downsampled image ready for upload.
class PickedImage {
  const PickedImage({required this.file, this.mimeType});

  final File file;

  /// Best-effort MIME type reported by the picker (e.g. `image/jpeg`).
  /// Passed on to Storage as `contentType` so objects are served with the
  /// right headers.
  final String? mimeType;
}

/// Thrown when picking fails for a reason other than the user cancelling
/// the picker. Callers can catch this to show feedback; a cancel is a
/// plain `null` return instead.
class PickImageException implements Exception {
  const PickImageException(this.cause);

  final Object cause;

  @override
  String toString() => 'PickImageException: $cause';
}

/// Picks and downsamples a gallery image for upload.
///
/// - `maxWidth`/`maxHeight` bound the resolution and `imageQuality`
///   recompresses, so typical cover photos land well under ~300 KB
///   (the picker re-encodes to JPEG for quality < 100).
/// - Returns `null` when the user cancels the picker.
/// - Throws [PickImageException] on real failures so callers can tell a
///   failure apart from a cancel and show feedback.
Future<PickedImage?> pickImage() async {
  try {
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (xFile == null) {
      return null; // cancelled by the user
    }
    return PickedImage(file: File(xFile.path), mimeType: xFile.mimeType);
  } catch (e, stackTrace) {
    AppLogger.error('picking image failed', error: e, stackTrace: stackTrace);
    throw PickImageException(e);
  }
}
