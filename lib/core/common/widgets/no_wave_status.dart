import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// An empty or failed state: a printer's mark, one sentence, and at most one
/// way forward.
///
/// The mark is the end mark's figure at status size - a small square between
/// two short hairlines - and it says which of the two this is before the
/// sentence is read:
///
/// * **hollow** (a hairline outline in the muted colour) when there is
///   nothing to do: an empty list, a search with no results;
/// * **filled orange** when the state comes with an action (retry, go back):
///   orange marks a position everywhere else in the app, and here the
///   position is "your move".
///
/// On arrival the hairlines draw outward from the square and the sentence
/// follows them up by [NoWaveSizes.entranceRise], `slow` in all, the sentence
/// [NoWaveMotion.strokeLag] behind - so a retry that fails again visibly
/// lands again instead of looking like nothing happened. Only paint moves:
/// the sentence and the action are laid out, tappable and read from the first
/// frame. With less motion asked for, everything is simply there.
class NoWaveStatus extends StatefulWidget {
  const NoWaveStatus({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;
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

  /// The hairlines: from the start, finishing [NoWaveMotion.strokeLag] early.
  late final CurvedAnimation _drawn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(
      0,
      1 - NoWaveMotion.strokeLag,
      curve: NoWaveMotionPolicy.curve,
    ),
  );

  /// The sentence and the action: [NoWaveMotion.strokeLag] behind the lines.
  late final CurvedAnimation _arrived = CurvedAnimation(
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
    _drawn.dispose();
    _arrived.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = NoWaveMotionPolicy.reducesMotion(context);
    final onAction = widget.onAction;
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (onAction != null) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          NoWaveButton(
            label: widget.actionLabel!,
            onPressed: onAction,
            variant: NoWaveButtonVariant.secondary,
          ),
        ],
      ],
    );
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: NoWaveStatusMark(
              actionable: onAction != null,
              drawn: still ? null : _drawn,
            ),
          ),
          const SizedBox(height: NoWaveSpacing.medium),
          if (still)
            words
          else
            AnimatedBuilder(
              animation: _arrived,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  0,
                  (1 - _arrived.value) * NoWaveSizes.entranceRise,
                ),
                child: child,
              ),
              child: FadeTransition(
                opacity: _arrived,
                // Arriving is paint only: a screen reader hears the state at
                // once, not after the fade.
                alwaysIncludeSemantics: true,
                child: words,
              ),
            ),
        ],
      ),
    );
  }
}

/// The status mark: a square between two short hairlines. Filled orange when
/// the state offers an action, a hollow outline when it does not.
///
/// [drawn] runs the hairlines outward from the square; without it they are
/// drawn already.
class NoWaveStatusMark extends StatelessWidget {
  const NoWaveStatusMark({super.key, required this.actionable, this.drawn});

  final bool actionable;
  final Animation<double>? drawn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.color ?? scheme.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rule(hairline, AlignmentDirectional.centerEnd),
        const SizedBox(width: NoWaveSpacing.small),
        SizedBox.square(
          key: const ValueKey('no-wave-status-mark'),
          dimension: NoWaveSizes.endMark,
          child: DecoratedBox(
            decoration: actionable
                ? const BoxDecoration(color: AppPalette.orange)
                : BoxDecoration(
                    border: Border.all(
                      color: scheme.onSurfaceVariant,
                      width: NoWaveStroke.hairline,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: NoWaveSpacing.small),
        _rule(hairline, AlignmentDirectional.centerStart),
      ],
    );
  }

  /// One hairline, growing away from the square: [anchor] is the end that
  /// touches it.
  Widget _rule(Color color, AlignmentDirectional anchor) {
    final line = SizedBox(
      width: NoWaveSizes.statusRule,
      height: NoWaveStroke.hairline,
      child: ColoredBox(color: color),
    );
    final drawn = this.drawn;
    if (drawn == null) return line;
    return AnimatedBuilder(
      animation: drawn,
      builder: (context, child) {
        final textDirection = Directionality.of(context);
        return Transform(
          alignment: anchor.resolve(textDirection),
          transform: Matrix4.diagonal3Values(drawn.value, 1, 1),
          child: child,
        );
      },
      child: line,
    );
  }
}
