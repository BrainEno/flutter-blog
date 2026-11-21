import 'dart:math' as math;

import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// An empty or failed state: one sentence, set like copy, and at most one way
/// forward.
///
/// No glyph, no ornament. The sentence is set in the serif at
/// [NoWaveTypeScale.sectionTitle], regular weight, centred in a short measure
/// ([NoWaveSizes.statusMeasure]) so it breaks into a compact block rather than
/// one long line - the way a magazine sets a pull quote, not the way a system
/// prints an alert. Tone comes from colour alone:
///
/// * **muted** when there is nothing to do (an empty list, no results): the
///   page is quiet because there is nothing to read;
/// * **ink**, with a bordered [NoWaveButton] under it, when the state comes
///   with an action (retry, sign in): it is addressed to the reader.
///
/// An optional [detail] sits under the sentence in the small sans of a
/// caption ([NoWaveTypography.metaLabel], muted): what will appear here, or
/// why. It belongs to the sentence, so it arrives with it and shares its
/// measure; pages no longer stack their own caption under a status.
///
/// On arrival the block fades in and rises [NoWaveSizes.entranceRise] over
/// `slow`, the button [NoWaveMotion.strokeLag] behind the words - so a retry
/// that fails again visibly lands again instead of looking like nothing
/// happened. Only paint moves: the sentence and the button are laid out,
/// tappable and read from the first frame. With less motion asked for,
/// everything is simply there.
class NoWaveStatus extends StatefulWidget {
  const NoWaveStatus({
    super.key,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;

  /// A caption under [message]: what will appear here, or why.
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<NoWaveStatus> createState() => _NoWaveStatusState();
}

class _NoWaveStatusState extends State<NoWaveStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NoWaveMotion.slow,
  );

  /// The sentence: from the start, finishing [NoWaveMotion.strokeLag] early.
  late final CurvedAnimation _words = CurvedAnimation(
    parent: _controller,
    curve: const Interval(
      0,
      1 - NoWaveMotion.strokeLag,
      curve: NoWaveMotionPolicy.curve,
    ),
  );

  /// The button: [NoWaveMotion.strokeLag] behind the sentence.
  late final CurvedAnimation _action = CurvedAnimation(
    parent: _controller,
    curve: const Interval(
      NoWaveMotion.strokeLag,
      1,
      curve: NoWaveMotionPolicy.curve,
    ),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NoWaveMotionPolicy.reducesMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _words.dispose();
    _action.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// [child] fading in and rising along [progress]; [child] itself when the
  /// reader asked for less motion.
  Widget _arrive(Animation<double> progress, Widget child, bool still) {
    if (still) return child;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (1 - progress.value) * NoWaveSizes.entranceRise),
        child: child,
      ),
      child: FadeTransition(
        opacity: progress,
        // Arriving is paint only: a screen reader hears the state at once,
        // not after the fade.
        alwaysIncludeSemantics: true,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = NoWaveMotionPolicy.reducesMotion(context);
    final scheme = Theme.of(context).colorScheme;
    final onAction = widget.onAction;
    final actionable = onAction != null;
    final detail = widget.detail;
    return Semantics(
      liveRegion: true,
      // Its own measure even where the parent stretches it (a list row).
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: _Measure(
          maxWidth: NoWaveSizes.statusMeasure,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _arrive(
                _words,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style:
                          NoWaveTypography.title(
                            context,
                            size: NoWaveTypeScale.sectionTitle,
                          ).copyWith(
                            fontWeight: FontWeight.w400,
                            color: actionable
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: NoWaveSpacing.small),
                      Text(
                        detail,
                        textAlign: TextAlign.center,
                        style: NoWaveTypography.metaLabel(
                          context,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                still,
              ),
              if (actionable) ...[
                const SizedBox(height: NoWaveSpacing.large),
                _arrive(
                  _action,
                  NoWaveButton(
                    label: widget.actionLabel!,
                    onPressed: onAction,
                    variant: NoWaveButtonVariant.secondary,
                  ),
                  still,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A `ConstrainedBox(maxWidth:)` that also reports its height at that width.
///
/// A plain `ConstrainedBox` answers intrinsic-height questions at the width it
/// is offered, not the narrower width it will lay its child out at. A status
/// in a `SliverFillRemaining(hasScrollBody: false)` is sized from that answer,
/// so a sentence that breaks into more lines at the measure than at the full
/// width would overflow. This asks at the measure.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({required this.maxWidth, super.child});

  final double maxWidth;

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      _RenderMeasure(BoxConstraints(maxWidth: maxWidth));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConstrainedBox renderObject,
  ) {
    renderObject.additionalConstraints = BoxConstraints(maxWidth: maxWidth);
  }
}

class _RenderMeasure extends RenderConstrainedBox {
  _RenderMeasure(BoxConstraints constraints)
    : super(additionalConstraints: constraints);

  double _at(double width) => math.min(width, additionalConstraints.maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(_at(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(_at(width));
}
