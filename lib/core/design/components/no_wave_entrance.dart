import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/widgets.dart';

/// The boundary of one list's entrance: the first time each of its first
/// [NoWaveMotion.entranceCount] items is built, it rises into place.
///
/// The scope remembers which positions already entered, so an item scrolled
/// out and back, or rebuilt by a refresh or a next page, holds still.
///
/// [generation] says what the list *is* (the feed kind, the query). When it
/// changes, items built from then on enter again: a different list is a new
/// entrance, a reloaded one is not. It is a value rather than a key on
/// purpose - re-keying would rebuild the scrollable under it and detach its
/// controller mid-frame.
class NoWaveEntranceScope extends StatefulWidget {
  const NoWaveEntranceScope({super.key, this.generation, required this.child});

  final Object? generation;
  final Widget child;

  @override
  State<NoWaveEntranceScope> createState() => NoWaveEntranceScopeState();
}

class NoWaveEntranceScopeState extends State<NoWaveEntranceScope> {
  final Set<int> _entered = {};

  @override
  void didUpdateWidget(covariant NoWaveEntranceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.generation != oldWidget.generation) _entered.clear();
  }

  /// How long the item at [index] waits before rising, or null when it does
  /// not animate: beyond the first screen, or already entered once.
  Duration? claim(int index) {
    if (index < 0 || index >= NoWaveMotion.entranceCount) return null;
    if (!_entered.add(index)) return null;
    return NoWaveMotion.stagger * index;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One item of a [NoWaveEntranceScope]: fades in while rising
/// [NoWaveSizes.entranceRise], [NoWaveMotion.stagger] after the one above it.
///
/// The type sets in like a page coming off the press rather than appearing in
/// one frame. Only paint moves - layout, hit testing and semantics are final
/// from the first frame, so a reader can tap or read an item mid-entrance.
/// Outside a scope, or with less motion asked for, the child is returned as
/// it is.
class NoWaveEntrance extends StatefulWidget {
  const NoWaveEntrance({super.key, required this.index, required this.child});

  /// Position in the list, 0 for the first item.
  final int index;
  final Widget child;

  @override
  State<NoWaveEntrance> createState() => _NoWaveEntranceState();
}

class _NoWaveEntranceState extends State<NoWaveEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (NoWaveMotionPolicy.reducesMotion(context)) return;
    final scope = context.findAncestorStateOfType<NoWaveEntranceScopeState>();
    final delay = scope?.claim(widget.index);
    if (delay == null) return;
    final total = delay + NoWaveMotion.slow;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    // The wait is the front of one curve, not a timer, so nothing is left
    // pending if the item is disposed before it enters.
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: NoWaveMotionPolicy.curve,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return widget.child;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, NoWaveSizes.entranceRise * (1 - progress.value)),
        child: Opacity(
          opacity: progress.value,
          // Readable from the first frame: a screen reader must not lose an
          // item because it is still fading in.
          alwaysIncludeSemantics: true,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
