import 'package:flutter/material.dart';

/// Editorial type roles. Latin display faces are bundled; CJK falls back to
/// the platform's serif faces, then the system font if those are unavailable.
abstract final class NoWaveTypography {
  static const serifFallback = <String>[
    'Noto Serif CJK SC',
    'Songti SC',
    'serif',
  ];

  static TextStyle title(BuildContext context, {double size = 24}) {
    return (Theme.of(context).textTheme.titleLarge ?? const TextStyle())
        .copyWith(
          fontFamily: 'InstrumentSerif',
          fontFamilyFallback: serifFallback,
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1.3,
        );
  }

  /// Latin display: Inter Tight 700 with tabular figures, so a counter does not
  /// jitter as its digits change.
  ///
  /// Tracking is expressed as a fraction of the size because the display face
  /// is used from 40 to 220pt and the optical weight of -0.05em only holds if
  /// it scales with the glyphs.
  static TextStyle display(
    BuildContext context, {
    double size = 96,
    Color? color,
    FontWeight weight = FontWeight.w700,
  }) {
    return (Theme.of(context).textTheme.displayLarge ?? const TextStyle())
        .copyWith(
          fontFamily: 'InterTight',
          fontSize: size,
          fontWeight: weight,
          height: 0.82,
          letterSpacing: -size * 0.05,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
  }

  /// The `Wave` half of the wordmark.
  ///
  /// Instrument Serif ships Regular and Italic only, so this never asks for a
  /// weight: a 600 here would be synthesized, and faux bold on a serif reads
  /// as a printing error rather than emphasis.
  static TextStyle serifItalic({double size = 40, Color? color}) {
    return TextStyle(
      fontFamily: 'InstrumentSerif',
      fontFamilyFallback: serifFallback,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
      fontSize: size,
      height: 1,
      color: color,
    );
  }

  /// The wordmark's `No` half, and any tracked-out meta line on ink.
  static TextStyle tight(
    BuildContext context, {
    double size = 40,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return (Theme.of(context).textTheme.titleLarge ?? const TextStyle())
        .copyWith(
          fontFamily: 'InterTight',
          fontSize: size,
          fontWeight: weight,
          height: 1,
          color: color,
        );
  }

  /// The line under the wordmark, and the label under the counter.
  ///
  /// CJK serif first: a Chinese line set in Inter Tight falls back to a sans
  /// face that fights the wordmark above it.
  static TextStyle splashMeta(
    BuildContext context, {
    double size = 13,
    Color? color,
  }) {
    return (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        .copyWith(
          fontFamily: 'InterTight',
          fontFamilyFallback: serifFallback,
          fontSize: size,
          height: 1.5,
          letterSpacing: size * 0.02,
          color: color,
        );
  }

  static TextStyle meta(BuildContext context) {
    return (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        .copyWith(
          fontFamily: 'InterTight',
          fontSize: 13,
          height: 1.45,
          letterSpacing: 0.2,
        );
  }
}
