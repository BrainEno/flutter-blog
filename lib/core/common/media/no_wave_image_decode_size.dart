import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The physical decode budget for one raster image.
///
/// Flutter keeps decoded frames in memory, not their compressed wire size. A
/// 4000 × 3000 photo therefore costs roughly 46 MiB as RGBA even when it is
/// displayed as a 56 dp list thumbnail. Supplying these values to image
/// providers lets the codec subsample on platforms that support it and keeps
/// the shared image cache proportional to the painted surface.
///
/// The size is deliberately expressed in *physical* pixels because that is
/// what `cacheWidth`, `cacheHeight`, `memCacheWidth`, and `memCacheHeight`
/// expect. Construct instances through the factories so device pixel ratio,
/// non-finite constraints, and an application-wide safety cap are handled in
/// the same way on every image surface.
@immutable
class NoWaveImageDecodeSize {
  const NoWaveImageDecodeSize._({required this.width, required this.height});

  /// A single image dimension above this is generally not useful in an app UI
  /// and can turn one maliciously large image into a memory-pressure event.
  ///
  /// This is a decode hint, not an upload transform: the original file remains
  /// intact for publishing and a decoder may choose a nearby native sampling
  /// size. The cap only applies to *display* copies.
  static const int maxDimension = 2048;

  /// Avoid requesting a zero-sized frame while a parent is laying out.
  static const int minDimension = 1;

  final int width;
  final int height;

  /// Calculates a decode size from a known logical paint rectangle.
  ///
  /// Use this for fixed design-token surfaces such as avatars, cover cards,
  /// and editor previews. [devicePixelRatio] is injectable so the arithmetic
  /// stays independently testable without a widget binding.
  factory NoWaveImageDecodeSize.fixed({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    int maximumDimension = maxDimension,
  }) {
    return NoWaveImageDecodeSize._(
      width: _physical(logicalWidth, devicePixelRatio, maximumDimension),
      height: _physical(logicalHeight, devicePixelRatio, maximumDimension),
    );
  }

  /// Calculates the budget from a layout constraint.
  ///
  /// Scrollable/inline content frequently has an infinite height. A sensible
  /// [fallbackLogicalHeight] prevents that unbounded constraint from turning
  /// into an unbounded decode request. Likewise a parent without a finite
  /// width receives [fallbackLogicalWidth].
  factory NoWaveImageDecodeSize.constraints({
    required BoxConstraints constraints,
    required double devicePixelRatio,
    required double fallbackLogicalWidth,
    required double fallbackLogicalHeight,
    int maximumDimension = maxDimension,
  }) {
    final width = _finitePositive(constraints.maxWidth)
        ? constraints.maxWidth
        : fallbackLogicalWidth;
    final height = _finitePositive(constraints.maxHeight)
        ? constraints.maxHeight
        : fallbackLogicalHeight;
    return NoWaveImageDecodeSize.fixed(
      logicalWidth: width,
      logicalHeight: height,
      devicePixelRatio: devicePixelRatio,
      maximumDimension: maximumDimension,
    );
  }

  /// A square thumbnail, avatar, or icon.
  factory NoWaveImageDecodeSize.square({
    required double logicalSide,
    required double devicePixelRatio,
    int maximumDimension = maxDimension,
  }) => NoWaveImageDecodeSize.fixed(
    logicalWidth: logicalSide,
    logicalHeight: logicalSide,
    devicePixelRatio: devicePixelRatio,
    maximumDimension: maximumDimension,
  );

  /// Limits this request to the original asset's real pixel dimensions.
  ///
  /// The media library exposes dimensions from the API. Honouring them avoids
  /// asking its CDN/codec to upscale a small source just because it is shown
  /// on a high-density display. Non-positive source dimensions mean "unknown"
  /// and retain the existing request.
  NoWaveImageDecodeSize boundedBySource({int? sourceWidth, int? sourceHeight}) {
    final boundedWidth = sourceWidth != null && sourceWidth > 0
        ? math.min(width, sourceWidth)
        : width;
    final boundedHeight = sourceHeight != null && sourceHeight > 0
        ? math.min(height, sourceHeight)
        : height;
    return NoWaveImageDecodeSize._(width: boundedWidth, height: boundedHeight);
  }

  static int _physical(double logical, double ratio, int maximum) {
    final safeMaximum = maximum.clamp(minDimension, maxDimension).toInt();
    final safeLogical = _finitePositive(logical)
        ? logical
        : minDimension.toDouble();
    final safeRatio = _finitePositive(ratio) ? ratio : 1.0;
    return (safeLogical * safeRatio)
        .ceil()
        .clamp(minDimension, safeMaximum)
        .toInt();
  }

  static bool _finitePositive(double value) => value.isFinite && value > 0;

  @override
  bool operator ==(Object other) =>
      other is NoWaveImageDecodeSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'NoWaveImageDecodeSize($width × $height)';
}

/// Reads display density at the widget edge, keeping the calculation itself
/// framework-light and reusable by widgets with no `BuildContext` dependency.
NoWaveImageDecodeSize noWaveDecodeSizeForFixed(
  BuildContext context, {
  required double logicalWidth,
  required double logicalHeight,
  int maximumDimension = NoWaveImageDecodeSize.maxDimension,
}) {
  return NoWaveImageDecodeSize.fixed(
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
    maximumDimension: maximumDimension,
  );
}
