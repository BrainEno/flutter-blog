import 'dart:typed_data';
import 'dart:ui';

import 'package:belog/core/common/media/cover_crop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A [width] × [height] JPEG, red on the left half and blue on the right, so a
/// cut can be told apart from the whole.
Uint8List _jpeg(int width, int height, {int? orientation}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x < width ~/ 2) {
        image.setPixelRgb(x, y, 255, 0, 0);
      } else {
        image.setPixelRgb(x, y, 0, 0, 255);
      }
    }
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image, quality: 95);
}

void main() {
  group('prepareCoverSource', () {
    test('an upright photo keeps its bytes and reports its size', () {
      final bytes = _jpeg(40, 20);
      final source = prepareCoverSource(bytes)!;
      expect(source.width, 40);
      expect(source.height, 20);
      expect(identical(source.bytes, bytes), isTrue);
      expect(source.size, const Size(40, 20));
    });

    test('a sideways camera photo is baked upright', () {
      // Orientation 6: stored landscape, shown rotated a quarter turn.
      final source = prepareCoverSource(_jpeg(40, 20, orientation: 6))!;
      expect(source.width, 20);
      expect(source.height, 40);
      final reread = img.decodeImage(source.bytes)!;
      expect(reread.width, 20);
      expect(reread.height, 40);
    });

    test('bytes the codec cannot read answer null', () {
      expect(prepareCoverSource(Uint8List.fromList([1, 2, 3, 4])), isNull);
      expect(prepareCoverSource(Uint8List(0)), isNull);
    });
  });

  group('cropCover', () {
    test('cuts the requested region at the frame ratio', () {
      final out = cropCover(
        CoverCropRequest(
          source: _jpeg(200, 100),
          // The left half: all red.
          rect: const Rect.fromLTWH(0, 0, 0.5, 0.625),
          aspectRatio: 16 / 10,
        ),
      )!;
      final cut = img.decodeImage(out)!;
      expect(cut.width, 100);
      // 100 / 1.6 = 62.5, rounded half away from zero.
      expect(cut.height, 63);
      expect(cut.width / cut.height, closeTo(16 / 10, 0.02));
      final middle = cut.getPixel(cut.width ~/ 2, cut.height ~/ 2);
      expect(middle.r, greaterThan(200));
      expect(middle.b, lessThan(60));
    });

    test('a wide cut is scaled down to the upload width', () {
      final out = cropCover(
        CoverCropRequest(
          source: _jpeg(2000, 1250),
          rect: const Rect.fromLTWH(0, 0, 1, 1),
          aspectRatio: 16 / 10,
        ),
      )!;
      final cut = img.decodeImage(out)!;
      expect(cut.width, CoverCropLimits.maxWidth);
      expect(cut.height, 1200);
    });

    test('an unreadable source answers null', () {
      expect(
        cropCover(
          CoverCropRequest(
            source: Uint8List.fromList([9, 9, 9]),
            rect: const Rect.fromLTWH(0, 0, 1, 1),
            aspectRatio: 16 / 10,
          ),
        ),
        isNull,
      );
    });
  });

  group('coverCropPixels', () {
    test('keeps the exact ratio and stays inside the source', () {
      final region = coverCropPixels(
        sourceWidth: 1000,
        sourceHeight: 1000,
        rect: const Rect.fromLTWH(0.9, 0.9, 0.5, 0.3125),
        aspectRatio: 16 / 10,
      );
      expect(region.width, 500);
      expect(region.height, 313);
      expect(region.left + region.width, lessThanOrEqualTo(1000));
      expect(region.top + region.height, lessThanOrEqualTo(1000));
    });

    test('a region taller than the source is shrunk, not moved out', () {
      final region = coverCropPixels(
        sourceWidth: 1600,
        sourceHeight: 900,
        rect: const Rect.fromLTWH(0, 0, 1, 1),
        aspectRatio: 16 / 10,
      );
      expect(region, const CoverCropPixels(0, 0, 1440, 900));
    });
  });

  test('clampCoverRect keeps the size and pulls the region inside', () {
    expect(
      clampCoverRect(const Rect.fromLTWH(0.8, -0.2, 0.5, 0.5)),
      const Rect.fromLTWH(0.5, 0, 0.5, 0.5),
    );
    expect(
      clampCoverRect(const Rect.fromLTWH(0, 0, 2, 1)),
      const Rect.fromLTWH(0, 0, 1, 1),
    );
  });

  group('centredCoverRect', () {
    test('a wide photo loses its sides', () {
      final rect = centredCoverRect(const Size(3200, 1000), 16 / 10);
      expect(rect.height, 1);
      expect(rect.width, closeTo(0.5, 1e-9));
      expect(rect.left, closeTo(0.25, 1e-9));
    });

    test('a tall photo loses its top and bottom', () {
      final rect = centredCoverRect(const Size(1000, 2000), 16 / 10);
      expect(rect.width, 1);
      expect(rect.height, closeTo(0.3125, 1e-9));
      expect(rect.top, closeTo((1 - 0.3125) / 2, 1e-9));
    });
  });
}
