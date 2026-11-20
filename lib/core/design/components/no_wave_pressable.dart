import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// A tappable surface that answers the finger, not only with an ink wash.
///
/// Material's ripple is a fine "I heard you", but on a flat editorial page it
/// is the only thing that moves, and it says nothing about *what* was touched.
/// This keeps the ripple (and with it keyboard focus, hover and semantics, all
/// from [InkWell]) and adds two small answers:
///
/// * while pressed, the content sinks to [NoWaveMotion.pressScale] - paper
///   giving under a finger - and springs back on release;
/// * while pressed, hovered or focused, a [NoWavePressArrow] inside steps
///   forward by [NoWaveSizes.arrowNudge], so the row points where it goes.
///
/// With less motion asked for, nothing scales and the arrow stays put; the
/// ripple and the focus wash still show the state.
class NoWavePressable extends StatefulWidget {
  const NoWavePressable({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.sink = true,
    required this.child,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Whether the content sinks while pressed. A card or a word sinks; a
  /// full-width row ruled at its top does not - scaling it would pull the rule
  /// in from the edges - and answers with its arrow and the wash instead.
  final bool sink;

  @override
  State<NoWavePressable> createState() => _NoWavePressableState();
}

class _NoWavePressableState extends State<NoWavePressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  void _update({bool? pressed, bool? hovered, bool? focused}) {
    final next = (
      pressed ?? _pressed,
      hovered ?? _hovered,
      focused ?? _focused,
    );
    if (next == (_pressed, _hovered, _focused)) return;
    setState(() {
      _pressed = next.$1;
      _hovered = next.$2;
      _focused = next.$3;
    });
  }

  @override
  Widget build(BuildContext context) {
    final still = NoWaveMotionPolicy.reducesMotion(context);
    final content = still || !widget.sink
        ? widget.child
        : AnimatedScale(
            scale: _pressed ? NoWaveMotion.pressScale : 1,
            duration: NoWaveMotion.fast,
            curve: NoWaveMotionPolicy.curve,
            child: widget.child,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHighlightChanged: (value) => _update(pressed: value),
        onHover: (value) => _update(hovered: value),
        onFocusChange: (value) => _update(focused: value),
        focusColor: AppPalette.orange.withAlpha(NoWaveOpacity.focusAlpha),
        hoverColor: AppPalette.orange.withAlpha(NoWaveOpacity.hoverAlpha),
        child: NoWavePressState(
          engaged: _pressed || _hovered || _focused,
          still: still,
          child: content,
        ),
      ),
    );
  }
}

/// Whether the nearest [NoWavePressable] is pressed, hovered or focused.
class NoWavePressState extends InheritedWidget {
  const NoWavePressState({
    super.key,
    required this.engaged,
    required this.still,
    required super.child,
  });

  /// Pressed, hovered or focused.
  final bool engaged;

  /// Less motion was asked for: show state without moving anything.
  final bool still;

  /// The nearest state, or null outside a [NoWavePressable].
  static NoWavePressState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoWavePressState>();

  @override
  bool updateShouldNotify(NoWavePressState oldWidget) =>
      engaged != oldWidget.engaged || still != oldWidget.still;
}

/// The trailing "this goes somewhere" arrow of a row or card.
///
/// Decorative - the row's own label says where it goes - so it is excluded
/// from semantics. Inside an engaged [NoWavePressable] it steps forward in the
/// reading direction; outside one it is a plain arrow.
class NoWavePressArrow extends StatelessWidget {
  const NoWavePressArrow({super.key});

  /// The arrow's offset, as a fraction of its own width, for [engaged] in
  /// [direction]. Forward is right in left-to-right text and left otherwise.
  static Offset offsetFor({
    required bool engaged,
    required TextDirection direction,
  }) {
    if (!engaged) return Offset.zero;
    final step = NoWaveSizes.arrowNudge / NoWaveIconSize.row;
    return Offset(direction == TextDirection.rtl ? -step : step, 0);
  }

  @override
  Widget build(BuildContext context) {
    const arrow = ExcludeSemantics(
      child: Icon(Icons.arrow_forward, size: NoWaveIconSize.row),
    );
    final state = NoWavePressState.maybeOf(context);
    if (state == null || state.still) return arrow;
    return AnimatedSlide(
      offset: offsetFor(
        engaged: state.engaged,
        direction: Directionality.of(context),
      ),
      duration: NoWaveMotion.fast,
      curve: NoWaveMotionPolicy.travel,
      child: arrow,
    );
  }
}
