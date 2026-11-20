import 'package:belog/core/design/design_tokens.dart';
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
class _ActivityStrip extends StatelessWidget {
  final ReadingStats stats;

  const _ActivityStrip({required this.stats});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final peak = stats.windowPeak;
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
            for (final day in stats.window)
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
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: day.count == 0
                                ? NoWaveSizes.activityBarEmpty
                                : day.count / peak,
                            widthFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: day.count == 0
                                    ? scheme.outlineVariant
                                    : scheme.primary,
                                borderRadius: BorderRadius.circular(
                                  NoWaveRadius.inline,
                                ),
                              ),
                            ),
                          ),
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
}
