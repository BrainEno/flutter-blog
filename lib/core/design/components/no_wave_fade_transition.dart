import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/material.dart';

/// Cross-fades [child] whenever [index] changes.
///
/// The four tabs are separate navigator stacks that keep their own scroll
/// position, so switching is a hard cut between two full-height trees. A fade
/// on the incoming stack keeps the tab bar still and stops the cut from
/// reading as a page reload - a slide would animate both trees at once.
///
/// With less motion asked for there is no transition at all: the child is not
/// wrapped, rather than wrapped in an animation shortened to nothing.
class NoWaveFadeTransition extends StatefulWidget {
  const NoWaveFadeTransition({
    super.key,
    required this.index,
    required this.child,
  });

  /// Which tab this is. A change of value restarts the fade.
  final int index;

  final Widget child;

  @override
  State<NoWaveFadeTransition> createState() => _NoWaveFadeTransitionState();
}

class _NoWaveFadeTransitionState extends State<NoWaveFadeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NoWaveMotion.normal,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-read on every dependency change, so flipping the OS switch mid-session
    // takes effect without a restart.
    _controller.duration = NoWaveMotionPolicy.resolve(
      context,
      NoWaveMotion.normal,
    );
  }

  @override
  void didUpdateWidget(covariant NoWaveFadeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (NoWaveMotionPolicy.reducesMotion(context)) return widget.child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: NoWaveMotionPolicy.curve,
      ),
      child: widget.child,
    );
  }
}
