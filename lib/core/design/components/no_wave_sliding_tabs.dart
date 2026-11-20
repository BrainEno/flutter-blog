import 'dart:math' as math;

import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// A row of words, one of them chosen, with the orange rule underneath it.
///
/// This is the in-page version of the bottom bar's [NoWaveTabIndicator]: the
/// same 2pt orange rule ([NoWaveSizes.accentRule]) riding on a hairline, as
/// wide as the chosen word. Choosing another word moves the rule like a pen
/// stroke. The edge on the side it is heading to leaves first; the other edge
/// follows [NoWaveMotion.strokeLag] later, so the rule stretches across the
/// gap and then gathers under the new word. A chip row swaps a fill; this
/// draws a line from where you were to where you are.
///
/// Every label gets a slot as wide as the label set at its *selected* weight,
/// measured before layout, and is set at the slot's start edge. Choosing a
/// word therefore never shifts its neighbours, and the rule knows where each word is in the same frame. With
/// large text the row scrolls sideways instead of wrapping, and a chosen word
/// that is off screen is scrolled into view.
///
/// The words are the semantics: each slot is a selected or unselected button
/// in a mutually exclusive group, and the rule is decoration. With less motion
/// asked for, the rule is placed instead of travelling and nothing scrolls by
/// animation.
class NoWaveSlidingTabs extends StatefulWidget {
  const NoWaveSlidingTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.inset = NoWaveSpacing.page,
  }) : assert(labels.length > 0),
       assert(selected >= 0 && selected < labels.length);

  /// The words, in reading order. Copy comes from the caller's ARB keys.
  final List<String> labels;

  /// Index of the chosen word.
  final int selected;

  /// Called with the index of a tapped word, including the chosen one; the
  /// caller decides whether anything changes (a word may need sign-in first).
  final ValueChanged<int> onSelected;

  /// Where the first word starts, measured from the row's leading edge. The
  /// default lines the words up with the page margin; the scroll area still
  /// runs to the edge so a long row scrolls under it.
  final double inset;

  /// The rule's leading and trailing edges at [t] of a move from [from] to
  /// [to], each given as (start, end) along the reading direction.
  ///
  /// The edge on the side of travel uses the first `1 - strokeLag` of the
  /// time; the other edge uses the last part. Both decelerate into place.
  static (double, double) ruleAt(
    (double, double) from,
    (double, double) to,
    double t,
  ) {
    const lead = Interval(
      0,
      1 - NoWaveMotion.strokeLag,
      curve: NoWaveMotionPolicy.travel,
    );
    const trail = Interval(
      NoWaveMotion.strokeLag,
      1,
      curve: NoWaveMotionPolicy.travel,
    );
    final forward = to.$1 >= from.$1;
    final startCurve = forward ? trail : lead;
    final endCurve = forward ? lead : trail;
    double lerp(double a, double b, Curve curve) =>
        a + (b - a) * curve.transform(t);
    return (lerp(from.$1, to.$1, startCurve), lerp(from.$2, to.$2, endCurve));
  }

  @override
  State<NoWaveSlidingTabs> createState() => _NoWaveSlidingTabsState();
}

/// One slot's geometry along the reading direction, from the row's start.
///
/// [lead] is the margin before the word inside its slot; the word is set
/// at the slot's start edge after it, so a word never moves when chosen.
typedef _Slot = ({double start, double width, double text, double lead});

class _NoWaveSlidingTabsState extends State<NoWaveSlidingTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: NoWaveMotion.slow,
    value: 1,
  );
  final _scroll = ScrollController();

  /// Slots as last laid out, so a move starts from what is on screen.
  List<_Slot> _slots = const [];

  /// Where the rule was when the current move began.
  (double, double)? _from;

  @override
  void didUpdateWidget(covariant NoWaveSlidingTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    // Start from what is on screen, even if an earlier move is unfinished.
    _from = _slots.length > oldWidget.selected
        ? _currentRule(oldWidget.selected)
        : null;
    if (NoWaveMotionPolicy.reducesMotion(context) || _from == null) {
      _travel.value = 1;
    } else {
      _travel.forward(from: 0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _travel.dispose();
    _scroll.dispose();
    super.dispose();
  }

  (double, double) _ruleFor(int index) {
    final slot = _slots[index];
    final start = slot.start + slot.lead;
    return (start, start + slot.text);
  }

  /// The rule as drawn now on its way to [target]: mid-move if a move is
  /// running, otherwise under [target].
  (double, double) _currentRule(int target) {
    final from = _from;
    if (from == null || _travel.value >= 1) return _ruleFor(target);
    return NoWaveSlidingTabs.ruleAt(from, _ruleFor(target), _travel.value);
  }

  /// Scrolls the chosen word fully into view, keeping the page margin.
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    if (widget.selected >= _slots.length) return;
    final position = _scroll.position;
    final slot = _slots[widget.selected];
    final leading = slot.start + _padding - widget.inset;
    final trailing = slot.start + slot.width + _padding + widget.inset;
    final viewport = position.viewportDimension;
    double? target;
    if (leading < position.pixels) {
      target = leading;
    } else if (trailing > position.pixels + viewport) {
      target = trailing - viewport;
    }
    if (target == null) return;
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    final duration = NoWaveMotionPolicy.resolve(context, NoWaveMotion.normal);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: duration,
        curve: NoWaveMotionPolicy.travel,
      );
    }
  }

  /// Padding before the first slot: the inset less the slot's own margin, so
  /// the first *word* starts at [NoWaveSlidingTabs.inset].
  double get _padding => math.max(0, widget.inset - NoWaveSpacing.small);

  /// The first slot's own margin: a full one when there is room for it, and
  /// only what the inset allows otherwise - inside an already padded column
  /// (`inset: 0`) the first word sits flush with the text above it.
  double get _firstLead => math.min(NoWaveSpacing.small, widget.inset);

  TextStyle _style(BuildContext context, {required bool selected}) {
    final scheme = Theme.of(context).colorScheme;
    return (Theme.of(context).textTheme.titleSmall ?? const TextStyle())
        .copyWith(
          fontFamily: 'InterTight',
          fontFamilyFallback: NoWaveTypography.serifFallback,
          fontSize: NoWaveTypeScale.label,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
  }

  List<_Slot> _measure(BuildContext context) {
    // The slot's AnimatedDefaultTextStyle replaces the inherited style, and
    // Text applies the platform's bold-text setting on top of it; measure
    // what will actually be drawn.
    final base = _style(context, selected: true);
    final style = MediaQuery.boldTextOf(context)
        ? base.merge(const TextStyle(fontWeight: FontWeight.bold))
        : base;
    final slots = <_Slot>[];
    var start = 0.0;
    for (final (index, label) in widget.labels.indexed) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final text = painter.width.ceilToDouble();
      painter.dispose();
      final lead = index == 0 ? _firstLead : NoWaveSpacing.small;
      final width = lead + text + NoWaveSpacing.small;
      slots.add((start: start, width: width, text: text, lead: lead));
      start += width;
    }
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots = _measure(context);
    final total = slots.last.start + slots.last.width;
    final scheme = Theme.of(context).colorScheme;
    final textDuration = NoWaveMotionPolicy.resolve(context, NoWaveMotion.fast);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: NoWaveStroke.hairline,
          ),
        ),
      ),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsetsDirectional.symmetric(horizontal: _padding),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: SizedBox(
            width: total,
            child: Stack(
              children: [
                Row(
                  children: [
                    for (final (index, label) in widget.labels.indexed)
                      SizedBox(
                        width: slots[index].width,
                        child: NoWaveSlidingTab(
                          label: label,
                          selected: index == widget.selected,
                          style: _style(
                            context,
                            selected: index == widget.selected,
                          ),
                          duration: textDuration,
                          lead: slots[index].lead,
                          onTap: () => widget.onSelected(index),
                        ),
                      ),
                  ],
                ),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  height: NoWaveSizes.accentRule,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: _travel,
                        builder: (context, _) {
                          final (start, end) = _currentRule(widget.selected);
                          return Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(start: start),
                              child: SizedBox(
                                key: const ValueKey('no-wave-sliding-rule'),
                                width: math.max(0, end - start),
                                height: NoWaveSizes.accentRule,
                                child: const ColoredBox(
                                  color: AppPalette.orange,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One word of a [NoWaveSlidingTabs]: at least a [NoWaveSizes.tapTarget]
/// tall, announced as a selected or unselected button of one group.
///
/// Public so tests and callers can find a word without matching the page
/// heading that may repeat it.
class NoWaveSlidingTab extends StatelessWidget {
  const NoWaveSlidingTab({
    super.key,
    required this.label,
    required this.selected,
    required this.style,
    required this.duration,
    required this.onTap,
    this.lead = NoWaveSpacing.small,
  });

  final String label;
  final bool selected;
  final TextStyle style;
  final Duration duration;
  final VoidCallback onTap;

  /// The margin before the word. The word is set at the start edge after it,
  /// so its position does not depend on its weight.
  final double lead;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: NoWavePressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: NoWaveSizes.tapTarget),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: lead,
                end: NoWaveSpacing.small,
              ),
              child: AnimatedDefaultTextStyle(
                style: style,
                duration: duration,
                curve: NoWaveMotionPolicy.curve,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
