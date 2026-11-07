import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// no-wave's two-face wordmark: `No` in Inter Tight 700, `Wave` in Instrument
/// Serif italic.
///
/// One widget so the app bar, the cold-start curtain and the startup failure
/// screen cannot drift into three slightly different brands. The size is a
/// parameter because the compact masthead and the curtain wordmark are the same
/// shape at different scales, not two different marks.
///
/// It carries no semantics of its own: a screen reader has nothing useful to do
/// with a decorative wordmark, so the callers that need a label put one around
/// it (see [NoWaveMasthead] and the curtain's single loading announcement).
class NoWaveWordmark extends StatelessWidget {
  const NoWaveWordmark({
    super.key,
    this.size = NoWaveSizes.masthead,
    this.color,
  });

  /// Cap height of the mark. `No` and `Wave` share it.
  final double size;

  /// Defaults to the surface's foreground so the mark inherits the theme.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.onSurface;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'No ',
            style: NoWaveTypography.tight(context, size: size, color: effective),
          ),
          TextSpan(
            text: 'Wave',
            style: NoWaveTypography.serifItalic(size: size, color: effective),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
