import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// A short orange rule that travels to the selected tab.
///
/// The tab bar's own indicator pill is switched off by the theme: a rounded
/// capsule is the one Material shape this design does not use. The selected
/// tab still needs a mark that is not colour or weight alone, and the web's
/// signature is a thin orange rule, so this draws one above the selected
/// destination and moves it there when the tab changes - the bar stays still,
/// the mark travels, the eye follows where it went.
///
/// It is decoration: the selection is already announced by the destination
/// itself, so the rule is excluded from semantics and from hit testing. With
/// less motion asked for the rule is placed rather than moved.
class NoWaveTabIndicator extends StatelessWidget {
  const NoWaveTabIndicator({
    super.key,
    required this.index,
    required this.count,
  }) : assert(count > 0),
       assert(index >= 0 && index < count);

  /// The selected destination, 0-based in reading order.
  final int index;

  /// How many destinations share the bar equally.
  final int count;

  /// Where the rule sits for [index] of [count] equal slots, as a directional
  /// alignment so the rule follows the bar in a right-to-left locale.
  static AlignmentDirectional alignmentFor(int index, int count) =>
      AlignmentDirectional(count == 1 ? 0 : -1 + 2 * index / (count - 1), 0);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          height: NoWaveSizes.accentRule,
          child: AnimatedAlign(
            alignment: alignmentFor(index, count),
            duration: NoWaveMotionPolicy.resolve(context, NoWaveMotion.normal),
            curve: NoWaveMotionPolicy.travel,
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              child: const Center(
                child: SizedBox(
                  width: NoWaveSizes.tabIndicator,
                  height: NoWaveSizes.accentRule,
                  child: ColoredBox(color: AppPalette.orange),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
