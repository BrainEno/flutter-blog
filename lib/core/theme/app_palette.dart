import 'package:flutter/material.dart';

// Spacing and the rest of the geometry live with the design tokens; this
// export keeps the screens that only import the palette compiling.
export 'package:belog/core/design/design_tokens.dart' show NoWaveSpacing;

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

  /// The 1dp seam between two curtain columns.
  ///
  /// Ink is #0F0D0C; this is the same ink lifted just enough to be drawn, so
  /// the columns read as separate sheets without a visible line on the app
  /// itself.
  static const curtainHairline = Color(0xFF2A2724);
  static const errorOnInk = Color(0xFFFFB4A5);

  /// A quiet filled area one step deeper than [surfaceOnPaper]: your own
  /// message, the draft being compared, an emphasised badge. Ink and the
  /// muted text both stay above 4.5:1 on it.
  static const tintOnPaper = Color(0xFFDDD5C7);

  /// The same step above [surfaceOnInk] on the dark page.
  static const tintOnInk = Color(0xFF2E2A26);

  /// Behind an error message: oxblood text stays above 4.5:1 on it.
  static const errorTintOnPaper = Color(0xFFF1D9D3);

  /// Behind an error message on ink, for [errorOnInk] text.
  static const errorTintOnInk = Color(0xFF3A1E19);
}
