import 'dart:math' as math;

import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/design/components/no_wave_sliding_tabs.dart';
import 'package:belog/core/design/components/no_wave_stamp_switcher.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/material.dart';

/// One destination of a [NoWaveTabBar].
@immutable
class NoWaveTabDestination {
  const NoWaveTabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// The outline drawn while the destination is not chosen.
  final IconData icon;

  /// The filled glyph stamped in when it is chosen.
  final IconData selectedIcon;
  final String label;
}

/// The app's bottom bar: the page's position mark, turned upside down.
///
/// Inside a page, a row of words stands on a hairline and the chosen word
/// carries an ink rule underneath ([NoWaveSlidingTabs]). The bottom bar is
/// the same idea seen from below: the bar hangs from a hairline along its top
/// edge, and the chosen destination carries a 2pt ink rule
/// ([NoWaveSizes.accentRule]) *on* that edge, as wide as its word. Choosing
/// another destination draws the rule across like a pen stroke - the leading
/// edge leaves first, the trailing edge follows [NoWaveMotion.strokeLag]
/// later ([NoWaveSlidingTabs.ruleAt]) - so the two navigation levels move the
/// same way and the app has one gesture for "you are here", not a pill here
/// and an underline there.
///
/// Under the rule, the chosen glyph is stamped from outline to fill
/// ([NoWaveStampSwitcher]) and its word turns to ink; the others stay muted
/// outlines. A slot sinks a little while pressed, like every other tappable
/// surface. With less motion asked for, the rule is placed and the glyph
/// swaps in one frame.
///
/// Each slot is announced as a button in a mutually exclusive group, selected
/// or not, named by its word. Tapping the chosen slot calls [onSelected] too:
/// the shell uses that to take the list back to its top.
class NoWaveTabBar extends StatefulWidget {
  const NoWaveTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(destinations.length > 1),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);

  final List<NoWaveTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<NoWaveTabBar> createState() => _NoWaveTabBarState();
}

class _NoWaveTabBarState extends State<NoWaveTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: NoWaveMotion.slow,
    value: 1,
  );

  /// The rule under each destination as last laid out, as (left, right).
  List<(double, double)> _rules = const [];

  /// Where the rule was when the current move began.
  (double, double)? _from;

  @override
  void didUpdateWidget(covariant NoWaveTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == oldWidget.selectedIndex) return;
    _from = _rules.length > oldWidget.selectedIndex
        ? _ruleNow(oldWidget.selectedIndex)
        : null;
    if (NoWaveMotionPolicy.reducesMotion(context) || _from == null) {
      _travel.value = 1;
    } else {
      _travel.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  /// The rule as drawn now on its way to [target].
  (double, double) _ruleNow(int target) {
    final from = _from;
    final to = _rules[target];
    if (from == null || _travel.value >= 1) return to;
    return NoWaveSlidingTabs.ruleAt(from, to, _travel.value);
  }

  TextStyle _labelStyle(BuildContext context, {required bool selected}) {
    final scheme = Theme.of(context).colorScheme;
    return TextStyle(
      fontFamily: 'InterTight',
      fontSize: NoWaveTypeScale.tabLabel,
      height: 1,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
    );
  }

  /// Each destination's rule, as wide as its word set at the chosen weight
  /// (and never narrower than the glyph), centred in its slot.
  List<(double, double)> _measure(BuildContext context, double width) {
    final count = widget.destinations.length;
    final slot = width / count;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final style = _labelStyle(context, selected: true);
    final scaler = MediaQuery.textScalerOf(context);
    final rules = <(double, double)>[];
    for (final (index, destination) in widget.destinations.indexed) {
      final painter = TextPainter(
        text: TextSpan(text: destination.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final word = math.min(
        slot - 2 * NoWaveSpacing.small,
        math.max(painter.width.ceilToDouble(), NoWaveIconSize.action),
      );
      painter.dispose();
      final column = rtl ? count - 1 - index : index;
      final centre = slot * column + slot / 2;
      rules.add((centre - word / 2, centre + word / 2));
    }
    return rules;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha);
    final textDuration = NoWaveMotionPolicy.resolve(context, NoWaveMotion.fast);
    // The words may grow with the reader's text size, but only so far: the
    // bar is a fixed band at the bottom of every screen, and past this its
    // glyph and word no longer fit the slot.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: hairline, width: NoWaveStroke.hairline),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: NoWaveSizes.tabBar,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _rules = _measure(context, constraints.maxWidth);
                  return Stack(
                    children: [
                      Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: Row(
                          children: [
                            for (final (index, destination)
                                in widget.destinations.indexed)
                              Expanded(
                                child: _TabSlot(
                                  destination: destination,
                                  selected: index == widget.selectedIndex,
                                  style: _labelStyle(
                                    context,
                                    selected: index == widget.selectedIndex,
                                  ),
                                  textDuration: textDuration,
                                  onTap: () => widget.onSelected(index),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // On the top hairline, over it: the rule replaces that
                      // stretch of the edge rather than floating under it.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: NoWaveSizes.accentRule,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: AnimatedBuilder(
                              animation: _travel,
                              builder: (context, _) {
                                final (left, right) = _ruleNow(
                                  widget.selectedIndex,
                                );
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(left: left),
                                    child: SizedBox(
                                      key: const ValueKey(
                                        'no-wave-tab-bar-rule',
                                      ),
                                      width: math.max(0, right - left),
                                      height: NoWaveSizes.accentRule,
                                      child: ColoredBox(
                                        color: scheme.onSurface,
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
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _maxTextScale = 1.6;
}

/// One destination: the glyph over its word, the whole slot the target.
class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.destination,
    required this.selected,
    required this.style,
    required this.textDuration,
    required this.onTap,
  });

  final NoWaveTabDestination destination;
  final bool selected;
  final TextStyle style;
  final Duration textDuration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: NoWavePressable(
        onTap: onTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: NoWaveStampSwitcher(
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    key: ValueKey(selected),
                    size: NoWaveIconSize.action,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: NoWaveSpacing.xs),
              AnimatedDefaultTextStyle(
                style: style,
                duration: textDuration,
                curve: NoWaveMotionPolicy.curve,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
