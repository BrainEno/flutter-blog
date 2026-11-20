import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/reading_stats.dart';
import 'package:flutter/material.dart';

/// The summary above the reading history: three figures, the longest streak
/// and a seven-day activity strip.
///
/// Every number comes from [ReadingStats], which is derived from rows already
/// on screen; the card stores nothing and never talks to the network. It is
/// purely presentational so the page decides when it is shown (never for an
/// empty history - the empty state already explains what will appear).
class ReadingStatsCard extends StatelessWidget {
  final ReadingStats stats;

  const ReadingStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.page,
        NoWaveSpacing.medium,
        NoWaveSpacing.page,
        NoWaveSpacing.small,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NoWaveRadius.container),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.readingStatsTitle,
                  style: const TextStyle(
                    fontSize: NoWaveTypeScale.sectionTitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: NoWaveSpacing.medium),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Figure(
                      key: const ValueKey('reading-stats-window'),
                      value: formatNumber(locale, stats.articlesInWindow),
                      label: l10n.readingStatsWindowLabel,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      key: const ValueKey('reading-stats-streak'),
                      value: formatNumber(locale, stats.currentStreakDays),
                      label: l10n.readingStatsStreakLabel,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      key: const ValueKey('reading-stats-total'),
                      value: formatNumber(locale, stats.totalArticles),
                      label: l10n.readingStatsTotalLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NoWaveSpacing.medium),
              _ActivityStrip(stats: stats),
              const SizedBox(height: NoWaveSpacing.small),
              Text(
                l10n.readingStatsLongest(stats.longestStreakDays),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: NoWaveSpacing.xs),
              Text(
                l10n.readingStatsFootnote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One figure: a large number over its caption, read as one phrase.
class _Figure extends StatelessWidget {
  final String value;
  final String label;

  const _Figure({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven bars, oldest day first, each labelled with its short weekday.
///
/// Screen readers get one sentence listing every day instead of fourteen
/// unlabeled boxes and captions.
///
/// When the card first appears the bars rise from the baseline one after
/// another, oldest to newest - the week is read left to right, so it is drawn
/// that way. Only paint moves: each bar's height is final from the first frame
/// and the rise is a vertical scale anchored at the baseline. When a removal
/// changes a day, that bar slides to its new height instead of jumping. With
/// less motion asked for, neither happens.
class _ActivityStrip extends StatefulWidget {
  final ReadingStats stats;

  const _ActivityStrip({required this.stats});

  @override
  State<_ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends State<_ActivityStrip>
    with SingleTickerProviderStateMixin {
  /// Half the list stagger between neighbouring bars: seven bars at a full
  /// stagger would still be rising after the reader has looked away.
  static final _barStagger = NoWaveMotion.stagger ~/ 2;

  AnimationController? _rise;

  /// Each bar's share of its height, in window order; empty once nothing
  /// moves.
  List<Animation<double>> _rises = const [];
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (NoWaveMotionPolicy.reducesMotion(context)) return;
    final total =
        _barStagger * (ReadingStats.windowDays - 1) + NoWaveMotion.slow;
    final rise = AnimationController(vsync: this, duration: total);
    _rise = rise;
    _rises = [
      for (var index = 0; index < ReadingStats.windowDays; index++)
        CurvedAnimation(
          parent: rise,
          curve: Interval(
            (_barStagger * index).inMicroseconds / total.inMicroseconds,
            (_barStagger * index + NoWaveMotion.slow).inMicroseconds /
                total.inMicroseconds,
            curve: NoWaveMotionPolicy.curve,
          ),
        ),
    ];
    rise.forward();
  }

  @override
  void dispose() {
    _rise?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final stats = widget.stats;
    final peak = stats.windowPeak;
    final reduce = NoWaveMotionPolicy.reducesMotion(context);
    final spoken = [
      for (final day in stats.window)
        l10n.readingStatsDay(formatWeekdayShort(locale, day.day), day.count),
    ].join(', ');
    return Semantics(
      container: true,
      label: l10n.readingStatsChart(spoken),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (index, day) in stats.window.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NoWaveSpacing.xs,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: NoWaveSizes.activityChart,
                        child: _bar(
                          heightFactor: day.count == 0
                              ? NoWaveSizes.activityBarEmpty
                              : day.count / peak,
                          color: day.count == 0
                              ? scheme.outlineVariant
                              : scheme.primary,
                          rise: reduce || index >= _rises.length
                              ? null
                              : _rises[index],
                          animateChanges: !reduce,
                        ),
                      ),
                      const SizedBox(height: NoWaveSpacing.xs),
                      Text(
                        formatWeekdayShort(locale, day.day),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar({
    required double heightFactor,
    required Color color,
    required Animation<double>? rise,
    required bool animateChanges,
  }) {
    Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(NoWaveRadius.inline),
      ),
    );
    if (rise != null) {
      bar = AnimatedBuilder(
        animation: rise,
        builder: (context, child) => Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(1, rise.value, 1),
          child: child,
        ),
        child: bar,
      );
    }
    if (!animateChanges) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: heightFactor,
          widthFactor: 1,
          child: bar,
        ),
      );
    }
    return AnimatedFractionallySizedBox(
      duration: NoWaveMotion.normal,
      curve: NoWaveMotionPolicy.curve,
      alignment: Alignment.bottomCenter,
      heightFactor: heightFactor,
      widthFactor: 1,
      child: bar,
    );
  }
}
