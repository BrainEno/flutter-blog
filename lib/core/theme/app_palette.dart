import 'package:flutter/material.dart';

/// The paper-and-ink palette shared with no-wave's editorial design system.
///
/// Orange is used for large surfaces and focus indicators; small accent text
/// on paper uses oxblood instead, because orange on paper does not meet 4.5:1.
abstract final class AppPalette {
  static const paper = Color(0xFFF2EEE6);
  static const ink = Color(0xFF0F0D0C);
  static const orange = Color(0xFFD8541F);
  static const oxblood = Color(0xFF8B1A10);

  static const mutedOnPaper = Color(0xFF5E5850);
  static const mutedOnInk = Color(0xFFB5AEA3);
  static const surfaceOnPaper = Color(0xFFE9E3D8);
  static const surfaceOnInk = Color(0xFF211E1B);
  static const errorOnInk = Color(0xFFFFB4A5);
}

/// Common mobile spacing; large text is allowed to reflow rather than clipped.
abstract final class NoWaveSpacing {
  static const page = 16.0;
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const section = 32.0;
}
