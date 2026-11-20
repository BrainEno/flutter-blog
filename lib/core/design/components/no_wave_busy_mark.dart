import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/material.dart';

/// "Working on it", the size of an icon: a short segment running along a
/// hairline, in the colour of the text around it.
///
/// This is the last piece of the no-spinner rule. Pages and sections already
/// say what they wait for in a sentence (`NoWaveLoadingLabel`); a button, a
/// row action or a send icon has no room for one, and used a small
/// `CircularProgressIndicator` instead. This takes the same slot and draws the
/// same figure as pull to refresh (`NoWaveRefresh`): a segment travelling
/// along a rule, start to end, like a line being set.
///
/// The mark is decoration. The control it sits in says it is busy - a
/// disabled button keeps its label - so it has no semantics unless
/// [semanticsLabel] is given for a slot that has nothing else to say. With
/// less motion asked for, the segment rests in the middle of the rule.
class NoWaveBusyMark extends StatefulWidget {
  const NoWaveBusyMark({
    super.key,
    this.size = NoWaveIconSize.inline,
    this.color,
    this.semanticsLabel,
  });

  /// The square it fills: the size of the icon it stands in for.
  final double size;

  /// The segment's colour. Defaults to the surrounding icon colour, so inside
  /// a button it is the button's own foreground.
  final Color? color;

  /// Read out when the mark is the only thing in its slot.
  final String? semanticsLabel;

  /// Where the segment's start edge is at [t] of one pass, as a share of the
  /// rule: wholly before the start at 0, wholly past the end at 1, so it
  /// enters and leaves rather than bouncing.
  static double segmentStart(double t) =>
      -NoWaveSizes.busySegment + (1 + NoWaveSizes.busySegment) * t;

  @override
  State<NoWaveBusyMark> createState() => _NoWaveBusyMarkState();
}

class _NoWaveBusyMarkState extends State<NoWaveBusyMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pass = AnimationController(
    vsync: this,
    duration: NoWaveMotion.enter,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (NoWaveMotionPolicy.reducesMotion(context)) {
      _pass.stop();
    } else if (!_pass.isAnimating) {
      _pass.repeat();
    }
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final still = NoWaveMotionPolicy.reducesMotion(context);
    final mark = SizedBox.square(
      dimension: widget.size,
      child: Center(
        child: SizedBox(
          height: NoWaveSizes.accentRule,
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: _BusyPainter(
                pass: _pass,
                still: still,
                color: color,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ),
    );
    final label = widget.semanticsLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(child: mark),
    );
  }
}

class _BusyPainter extends CustomPainter {
  _BusyPainter({
    required this.pass,
    required this.still,
    required this.color,
    required this.textDirection,
  }) : super(repaint: pass);

  final Animation<double> pass;
  final bool still;
  final Color color;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()..color = color.withAlpha(NoWaveOpacity.dividerAlpha);
    canvas.drawRect(Offset.zero & size, rule);

    final length = size.width * NoWaveSizes.busySegment;
    final share = still
        ? (1 - NoWaveSizes.busySegment) / 2
        : NoWaveBusyMark.segmentStart(
            NoWaveMotionPolicy.travel.transform(pass.value),
          );
    var left = size.width * share;
    if (textDirection == TextDirection.rtl) {
      left = size.width - left - length;
    }
    canvas.drawRect(
      Rect.fromLTWH(left, 0, length, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BusyPainter old) =>
      old.still != still ||
      old.color != color ||
      old.textDirection != textDirection;
}
