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
