import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// A picked photo ready to frame: upright bytes and their pixel size.
///
/// A camera JPEG often stores its pixels sideways and an EXIF tag that says
/// how to turn them. The crop frame works in what the author sees, so a
/// sideways original is baked upright once, here, and every later step - the
/// on-screen frame, the cut, the upload - reads the same pixels.
@immutable
class CoverSource {
  const CoverSource({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  Size get size => Size(width.toDouble(), height.toDouble());
}

/// One cut: which part of [source] to keep, as shares of its width and
/// height, and the frame it must come out in.
@immutable
class CoverCropRequest {
  const CoverCropRequest({
    required this.source,
    required this.rect,
    required this.aspectRatio,
  });

  final Uint8List source;

  /// The kept region in 0..1 coordinates of the upright source.
  final Rect rect;

  /// Width over height of the result, e.g. the reader's cover frame.
  final double aspectRatio;
}

/// Limits of the cut cover, matching what the picker already hands over.
abstract final class CoverCropLimits {
  /// Widest the cut cover is encoded: a reader header on a tablet, at most.
  static const maxWidth = 1920;

  /// JPEG quality of the cut cover; the server transcodes it to WebP anyway.
  static const jpegQuality = 85;

  /// MIME type of every cut cover.
  static const mimeType = 'image/jpeg';
}

/// Decodes [bytes] and turns a sideways camera photo upright.
///
/// Answers null for a file the codec cannot read (an exotic format the picker
/// passed through untouched); the caller then keeps the photo uncut. An
/// already-upright photo keeps its original bytes: nothing is re-encoded until
/// the author actually cuts it.
CoverSource? prepareCoverSource(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return null;
  }
  final ifd = decoded.exif.imageIfd;
  final sideways = ifd.hasOrientation && ifd.orientation != 1;
  if (!sideways) {
    return CoverSource(
      bytes: bytes,
      width: decoded.width,
      height: decoded.height,
    );
  }
  final upright = img.bakeOrientation(decoded);
  return CoverSource(
    bytes: img.encodeJpg(upright, quality: CoverCropLimits.jpegQuality),
    width: upright.width,
    height: upright.height,
  );
}

/// Cuts [request] out of its source and encodes it as a JPEG.
///
/// The result has exactly the requested aspect ratio (to the pixel) and is no
/// wider than [CoverCropLimits.maxWidth]. Answers null when the source cannot
/// be decoded.
Uint8List? cropCover(CoverCropRequest request) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(request.source);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final region = coverCropPixels(
    sourceWidth: upright.width,
    sourceHeight: upright.height,
    rect: request.rect,
    aspectRatio: request.aspectRatio,
  );
  var cut = img.copyCrop(
    upright,
    x: region.left,
    y: region.top,
    width: region.width,
    height: region.height,
  );
  if (cut.width > CoverCropLimits.maxWidth) {
    cut = img.copyResize(
      cut,
      width: CoverCropLimits.maxWidth,
      height: (CoverCropLimits.maxWidth / request.aspectRatio).round(),
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodeJpg(cut, quality: CoverCropLimits.jpegQuality);
}

/// A whole-pixel region of the source.
@immutable
class CoverCropPixels {
  const CoverCropPixels(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CoverCropPixels &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'CoverCropPixels($left, $top, $width × $height)';
}

/// Turns a 0..1 [rect] into whole source pixels of exactly [aspectRatio].
///
/// The frame on screen already has that ratio, so this only absorbs rounding:
/// the height follows the rounded width, and the region is shrunk (never
/// moved outside) to stay within the source.
CoverCropPixels coverCropPixels({
  required int sourceWidth,
  required int sourceHeight,
  required Rect rect,
  required double aspectRatio,
}) {
  final clamped = clampCoverRect(rect);
  var width = math.max(1, (clamped.width * sourceWidth).round());
  var height = math.max(1, (width / aspectRatio).round());
  if (height > sourceHeight) {
    height = sourceHeight;
    width = math.max(1, (height * aspectRatio).round());
  }
  width = math.min(width, sourceWidth);
  final left = (clamped.left * sourceWidth)
      .round()
      .clamp(0, sourceWidth - width)
      .toInt();
  final top = (clamped.top * sourceHeight)
      .round()
      .clamp(0, sourceHeight - height)
      .toInt();
  return CoverCropPixels(left, top, width, height);
}

/// [rect] limited to the unit square, keeping its size where it fits.
Rect clampCoverRect(Rect rect) {
  final width = rect.width.clamp(0.0, 1.0).toDouble();
  final height = rect.height.clamp(0.0, 1.0).toDouble();
  final left = rect.left.clamp(0.0, 1.0 - width).toDouble();
  final top = rect.top.clamp(0.0, 1.0 - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

/// The largest centred region of a [source]-sized image with [aspectRatio],
/// in 0..1 coordinates: where the frame starts before the author moves it.
Rect centredCoverRect(Size source, double aspectRatio) {
  final sourceAspect = source.width / source.height;
  if (sourceAspect > aspectRatio) {
    final width = aspectRatio / sourceAspect;
    return Rect.fromLTWH((1 - width) / 2, 0, width, 1);
  }
  final height = sourceAspect / aspectRatio;
  return Rect.fromLTWH(0, (1 - height) / 2, 1, height);
}

/// Runs the codec work off the UI thread.
///
/// A class rather than two functions so a widget test can answer at once
/// instead of waiting for a real isolate.
class CoverCropper {
  const CoverCropper();

  Future<CoverSource?> prepare(Uint8List bytes) =>
      compute(prepareCoverSource, bytes);

  Future<Uint8List?> crop(CoverCropRequest request) =>
      compute(cropCover, request);
}
