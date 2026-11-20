import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/material.dart';

/// Remembers which list was scrolled last, so tapping the tab you are already
/// on can take that list back to its top.
///
/// Every platform's tab bar does this, and readers try it without thinking:
/// deep in the feed, tap "Home" again to get back to the newest articles. The
/// shell wraps its branches in this widget and calls
/// [NoWaveReturnToTopState.toTop] when the active destination is tapped again. It keeps the stack -
/// nothing is popped - and moves only the list on screen:
///
/// * it follows vertical scroll notifications rather than taking a
///   controller, so every page works without being rewired, including pages
///   whose list owns its controller for paging;
/// * it remembers one list per [section] (the shell passes its branch index),
///   because every branch stays alive off screen: re-tapping "Search" must
///   not move the feed hidden behind it;
/// * it does nothing when the list it remembers is under another page (its
///   route is not current) or already at the top;
/// * from far down it first jumps to [NoWaveMotion.returnLeap] screens from
///   the top and travels only that last stretch, so the return reads as one
///   short movement instead of a long blur of every article in between;
/// * with less motion asked for, it jumps straight to the top.
class NoWaveReturnToTop extends StatefulWidget {
  const NoWaveReturnToTop({
    super.key,
    required this.section,
    required this.child,
  });

  /// Which section is on screen; scrolls are remembered per section.
  final int section;

  final Widget child;

  /// Where the travelling part of a return starts, for a list at [pixels]
  /// with its top at [top] and [viewport] tall: no closer than it already is,
  /// and no farther than [NoWaveMotion.returnLeap] screens.
  static double travelFrom({
    required double pixels,
    required double top,
    required double viewport,
  }) {
    final leap = top + viewport * NoWaveMotion.returnLeap;
    return pixels < leap ? pixels : leap;
  }

  @override
  State<NoWaveReturnToTop> createState() => NoWaveReturnToTopState();
}

class NoWaveReturnToTopState extends State<NoWaveReturnToTop> {
  /// Per section, the context of the last vertical list that scrolled.
  final Map<int, BuildContext> _last = {};

  bool _track(ScrollNotification notification) {
    final context = notification.context;
    if (notification.metrics.axis == Axis.vertical && context != null) {
      _last[widget.section] = context;
    }
    return false;
  }

  /// Takes the last scrolled list back to its top. Returns whether anything
  /// moved, so a caller can decide what an idle tap should do instead.
  bool toTop() {
    final context = _last[widget.section];
    if (context == null || !context.mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    final top = position.minScrollExtent;
    if (position.pixels <= top) return false;
    if (NoWaveMotionPolicy.reducesMotion(this.context)) {
      position.jumpTo(top);
      return true;
    }
    final from = NoWaveReturnToTop.travelFrom(
      pixels: position.pixels,
      top: top,
      viewport: position.viewportDimension,
    );
    if (from != position.pixels) position.jumpTo(from);
    unawaited(
      position.animateTo(
        top,
        duration: NoWaveMotion.slow,
        curve: NoWaveMotionPolicy.travel,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _track,
      child: widget.child,
    );
  }
}
