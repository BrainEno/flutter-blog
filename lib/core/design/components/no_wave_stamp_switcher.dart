import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/widgets.dart';

/// Swaps a toggle's glyph like a rubber stamp: the new state lands slightly
/// large ([NoWaveMotion.stampScale]) and settles while it inks in; the old one
/// lifts off and fades.
///
/// Saving an article is a small commitment, and an icon that silently swaps
/// outlines for a fill is easy to miss. The stamp is short
/// ([NoWaveMotion.normal]) so a quick second tap still feels immediate.
///
/// [child] must carry a key that changes with the state - `ValueKey(isSaved)`
/// - because that is how the switcher tells a new state from a rebuild. With
/// less motion asked for the glyph swaps in one frame.
class NoWaveStampSwitcher extends StatelessWidget {
  const NoWaveStampSwitcher({super.key, required this.child});

  final Widget child;

  static Widget _stamp(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: NoWaveMotion.stampScale,
          end: 1,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (NoWaveMotionPolicy.reducesMotion(context)) return child;
    return AnimatedSwitcher(
      duration: NoWaveMotion.normal,
      switchInCurve: NoWaveMotionPolicy.curve,
      switchOutCurve: NoWaveMotionPolicy.curve,
      transitionBuilder: _stamp,
      child: child,
    );
  }
}
