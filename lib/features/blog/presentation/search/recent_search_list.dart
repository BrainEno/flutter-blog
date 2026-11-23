import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// The recent searches under an empty search field: a quiet label with a
/// "clear" link, then one row per search - tap the words to search again,
/// or the cross at the end to take that one off the list.
class RecentSearchList extends StatelessWidget {
  const RecentSearchList({
    super.key,
    required this.queries,
    required this.onSelect,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> queries;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      key: const ValueKey('recent-searches'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.recentSearchesTitle,
                  style: NoWaveTypography.metaLabel(context, color: muted),
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                padding: const EdgeInsetsDirectional.only(
                  start: NoWaveSpacing.small,
                ),
                minimumSize: const Size(0, NoWaveSizes.tapTarget),
              ),
              onPressed: onClear,
              child: Text(l10n.actionClear),
            ),
          ],
        ),
        for (final query in queries)
          _RecentSearchRow(
            query: query,
            onSelect: () => onSelect(query),
            onRemove: () => onRemove(query),
          ),
      ],
    );
  }
}

class _RecentSearchRow extends StatelessWidget {
  const _RecentSearchRow({
    required this.query,
    required this.onSelect,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: l10n.recentSearchAgain(query),
            excludeSemantics: true,
            child: InkWell(
              onTap: onSelect,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: NoWaveSizes.tapTarget,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      size: NoWaveIconSize.inline,
                      color: muted,
                    ),
                    const SizedBox(width: NoWaveSpacing.medium),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NoWaveSpacing.xs,
                        ),
                        child: Text(
                          query,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: NoWaveTypography.title(
                            context,
                            size: NoWaveTypeScale.actionRow,
                          ).copyWith(fontWeight: FontWeight.w400),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.recentSearchRemove(query),
          icon: Icon(Icons.close, size: NoWaveIconSize.inline, color: muted),
          onPressed: onRemove,
        ),
      ],
    );
  }
}
