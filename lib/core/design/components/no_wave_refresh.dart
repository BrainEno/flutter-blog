import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pull to refresh, drawn as a rule instead of a spinner.
///
/// The stock indicator drops a spinning disc over the list: the one element
/// on screen that belongs to no typeface and no palette, and the very thing
/// `no_spinner_test.dart` keeps out of every page. This keeps the platform's
/// gesture - Flutter's own [RefreshIndicator.noSpinner] decides when a pull
/// starts, arms, bounces back on iOS and runs [onRefresh] - and replaces only
/// what is drawn, along the top edge of the list:
///
/// * **pulling**: a hairline-coloured rule grows from the centre outwards as
///   far as the pull has gone toward the release point;
/// * **ready**: past the release point the rule turns orange and reaches both
///   edges, with a light selection click - "let go now", said without a word;
/// * **refreshing**: an orange segment runs along the edge like type being
///   set, start to end, until [onRefresh] completes;
/// * **done / cancelled**: the rule fades away.
///
/// The rule is decoration. While refreshing, a live region carries the
/// platform's own localized "refresh" label, so a screen reader hears that
/// something is happening; nothing else is announced. With less motion asked
/// for the segment does not run - the armed rule simply stays until done.
class NoWaveRefresh extends StatefulWidget {
  const NoWaveRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  /// Runs when a pull is released past the release point. The rule runs
  /// until the returned future completes.
  final RefreshCallback onRefresh;

  /// The scrollable this refreshes. It must be able to overscroll at the top
  /// (`AlwaysScrollableScrollPhysics` for a list that may be short).
  final Widget child;

  /// Which scroll notifications count, as for [RefreshIndicator].
  final ScrollNotificationPredicate notificationPredicate;

  /// How far toward the release point a pull of [pulled] logical pixels is,
  /// in a viewport [viewport] tall: 0 at rest, 1 where letting go refreshes.
  ///
  /// Mirrors the framework's own arithmetic: a released drag refreshes once
  /// it has pulled a quarter of the viewport (`RefreshIndicator`'s
  /// `_kDragContainerExtentPercentage`). Its earlier "armed" report only
  /// fades its spinner in, and letting go there still cancels on Android, so
  /// the rule does not turn orange until this reaches 1.
  static double pullProgress(double pulled, double viewport) {
    if (viewport <= 0) return 0;
    return (pulled / (viewport * _releaseShare)).clamp(0.0, 1.0);
  }

  /// `RefreshIndicator`'s `_kDragContainerExtentPercentage`.
  static const _releaseShare = 0.25;

  @override
  State<NoWaveRefresh> createState() => _NoWaveRefreshState();
}

class _NoWaveRefreshState extends State<NoWaveRefresh>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: NoWaveMotion.enter,
  );

  RefreshIndicatorStatus? _status;

  /// Logical pixels pulled past the top since the current drag started.
  double _pulled = 0;
  double _viewport = 0;

  /// Whether the rule is fading out after a finished or abandoned pull.
  bool _leaving = false;

  /// Whether the list bounces past its top (iOS, macOS) rather than clamping.
  bool _bounces = false;

  /// Pulled past the point where letting go refreshes.
  ///
  /// Where the list bounces, the framework refreshes as soon as an armed pull
  /// springs back, so "armed" is already the release point there.
  bool get _ready => switch (_status) {
    RefreshIndicatorStatus.armed when _bounces => true,
    RefreshIndicatorStatus.drag || RefreshIndicatorStatus.armed =>
      NoWaveRefresh.pullProgress(_pulled, _viewport) >= 1,
    _ => false,
  };

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _onStatus(RefreshIndicatorStatus? status) {
    if (!mounted) return;
    final reduce = NoWaveMotionPolicy.reducesMotion(context);
    // The framework reports `snap` and then runs the refresh without a
    // separate report, so the segment starts at the snap.
    if (status == RefreshIndicatorStatus.snap && !reduce) {
      unawaited(_sweep.repeat());
    } else {
      _sweep.stop();
    }
    final ending =
        status == RefreshIndicatorStatus.done ||
        status == RefreshIndicatorStatus.canceled;
    setState(() {
      if (status == RefreshIndicatorStatus.drag) {
        _pulled = 0;
        _bounces = false;
      }
      // With less motion there is no fade to wait for: the rule just goes.
      _status = ending && reduce ? null : status;
      _leaving = ending && !reduce;
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return false;
    if (_status != RefreshIndicatorStatus.drag &&
        _status != RefreshIndicatorStatus.armed) {
      return false;
    }
    if (notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    final delta = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta?) => -scrollDelta,
      OverscrollNotification(:final overscroll) => -overscroll,
      _ => 0.0,
    };
    if (delta != 0) {
      final wasReady = _ready;
      setState(() {
        if (notification.metrics.outOfRange) _bounces = true;
        _pulled = (_pulled + delta).clamp(0.0, double.infinity);
        _viewport = notification.metrics.viewportDimension;
      });
      if (_ready && !wasReady) unawaited(HapticFeedback.selectionClick());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = _status == RefreshIndicatorStatus.snap;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator.noSpinner(
            onRefresh: widget.onRefresh,
            onStatusChange: _onStatus,
            notificationPredicate: widget.notificationPredicate,
            child: widget.child,
          ),
        ),
        if (_status != null)
          PositionedDirectional(
            start: 0,
            end: 0,
            top: 0,
            height: NoWaveSizes.accentRule,
            // While refreshing, the platform's own localized "refresh" label
            // is announced once; the rule itself is never read.
            child: Semantics(
              container: true,
              liveRegion: refreshing,
              label: refreshing
                  ? MaterialLocalizations.of(
                      context,
                    ).refreshIndicatorSemanticLabel
                  : null,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedOpacity(
                    opacity: _leaving ? 0 : 1,
                    duration: NoWaveMotionPolicy.resolve(
                      context,
                      NoWaveMotion.normal,
                    ),
                    curve: NoWaveMotionPolicy.curve,
                    onEnd: () {
                      if (_leaving && mounted) {
                        setState(() {
                          _status = null;
                          _leaving = false;
                        });
                      }
                    },
                    child: _rule(context, refreshing: refreshing),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _rule(BuildContext context, {required bool refreshing}) {
    final armed =
        refreshing || _ready || _status == RefreshIndicatorStatus.done;
    if (refreshing && _sweep.isAnimating) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final segment = width * NoWaveSizes.refreshSegment;
          return AnimatedBuilder(
            animation: _sweep,
            builder: (context, _) {
              // From wholly before the start edge to wholly past the end.
              final t = NoWaveMotionPolicy.travel.transform(_sweep.value);
              return Stack(
                children: [
                  PositionedDirectional(
                    start: -segment + (width + segment) * t,
                    top: 0,
                    bottom: 0,
                    width: segment,
                    child: const ColoredBox(
                      key: ValueKey('no-wave-refresh-segment'),
                      color: AppPalette.orange,
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    }
    final progress = armed
        ? 1.0
        : NoWaveRefresh.pullProgress(_pulled, _viewport);
    final color = armed
        ? AppPalette.orange
        : Theme.of(context).colorScheme.outline;
    return Center(
      child: FractionallySizedBox(
        widthFactor: progress,
        // Centre loosens the height too; the rule keeps the full thickness.
        heightFactor: 1,
        child: ColoredBox(
          key: const ValueKey('no-wave-refresh-rule'),
          color: color,
        ),
      ),
    );
  }
}
