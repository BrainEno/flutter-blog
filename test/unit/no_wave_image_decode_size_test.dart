import 'package:belog/core/common/media/no_wave_image_decode_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoWaveImageDecodeSize', () {
    test('converts logical paint size to physical cache pixels', () {
      final size = NoWaveImageDecodeSize.fixed(
        logicalWidth: 56,
        logicalHeight: 56,
        devicePixelRatio: 2.5,
      );

      expect(size.width, 140);
      expect(size.height, 140);
    });

    test('caps extreme source-independent display requests', () {
      final size = NoWaveImageDecodeSize.fixed(
        logicalWidth: 4000,
        logicalHeight: 3000,
        devicePixelRatio: 3,
      );

      expect(size.width, NoWaveImageDecodeSize.maxDimension);
      expect(size.height, NoWaveImageDecodeSize.maxDimension);
    });

    test('uses finite fallbacks for unbounded layout constraints', () {
      final size = NoWaveImageDecodeSize.constraints(
        constraints: const BoxConstraints(),
        devicePixelRatio: 2,
        fallbackLogicalWidth: 120,
        fallbackLogicalHeight: 160,
      );

      expect(size.width, 240);
      expect(size.height, 320);
    });

    test('never asks the codec to upscale a known small source', () {
      final size = NoWaveImageDecodeSize.fixed(
        logicalWidth: 300,
        logicalHeight: 300,
        devicePixelRatio: 2,
      ).boundedBySource(sourceWidth: 80, sourceHeight: 120);

      expect(size.width, 80);
      expect(size.height, 120);
    });

    test('invalid measurements still produce a valid minimum hint', () {
      final size = NoWaveImageDecodeSize.fixed(
        logicalWidth: double.nan,
        logicalHeight: double.infinity,
        devicePixelRatio: 0,
      );

      expect(size.width, 1);
      expect(size.height, 1);
    });
  });
}
