import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// A hairline across the top of [child] that fills as the reader scrolls.
///
/// A long article has no other sense of "how much is left": the scroll thumb
/// is hidden on phones and the page has no page numbers. The line is the
/// printed answer - a rule under the masthead, orange like every other mark
/// of position in the app.
///
/// It follows the outermost vertical scrollable under it (notification depth
/// 0), so a code block that scrolls sideways or a nested list does not move
/// it. Metric changes count as well as scrolls: an image that finishes loading
/// makes the article longer, and the line should shrink back to the truth
/// without waiting for the next drag.
///
/// The line is driven by the finger, not by a clock, so there is nothing to
/// switch off for less motion. It is decoration and excluded from semantics:
/// a screen reader moves by element and announces its own position.
class NoWaveReadingProgress extends StatefulWidget {
  const NoWaveReadingProgress({super.key, required this.child});

  final Widget child;

  /// The share of [metrics] already read, from 0 to 1.
  ///
  /// A page that does not scroll counts as unread rather than finished: a
  /// full bar on an article nobody has moved through would be a lie.
  static double fractionOf(ScrollMetrics metrics) {
    final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (!extent.isFinite || extent <= 0) return 0;
    final read = (metrics.pixels - metrics.minScrollExtent) / extent;
    return read.clamp(0.0, 1.0);
  }

  @override
  State<NoWaveReadingProgress> createState() => _NoWaveReadingProgressState();
}

class _NoWaveReadingProgressState extends State<NoWaveReadingProgress> {
  final ValueNotifier<double> _fraction = ValueNotifier<double>(0);

  bool _track(ScrollMetrics metrics, int depth) {
    if (depth == 0 && metrics.axis == Axis.vertical) {
      _fraction.value = NoWaveReadingProgress.fractionOf(metrics);
    }
    // Never consume: the page and its other listeners still see the scroll.
    return false;
  }

  @override
  void dispose() {
    _fraction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _track(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _track(n.metrics, n.depth),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: SizedBox(
                      height: NoWaveSizes.accentRule,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _fraction,
                        builder: (context, fraction, _) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FractionallySizedBox(
                            widthFactor: fraction,
                            heightFactor: 1,
                            child: const ColoredBox(color: AppPalette.orange),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
