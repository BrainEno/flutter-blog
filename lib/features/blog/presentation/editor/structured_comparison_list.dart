import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison_list.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_value.dart';
import 'package:flutter/material.dart';

/// Ordinal item view: unlike blocks, list items lack stable IDs. Show only
/// changed rows, while the original full fields remain available on the card.
class StructuredComparisonList extends StatelessWidget {
  const StructuredComparisonList({super.key, required this.items});
  final List<StructuredListItemComparison> items;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final changed = items.where((item) => item.changed).toList(growable: false);
    if (changed.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text(l10n.structuredCompareListDetails),
      subtitle: Text(l10n.structuredCompareListNote),
      childrenPadding: const EdgeInsets.all(NoWaveSpacing.small),
      children: [
        for (final item in changed)
          ExpansionTile(
            title: Text('${l10n.structuredCompareListItem} ${item.index + 1}'),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            childrenPadding: const EdgeInsets.all(NoWaveSpacing.small),
            children: [
              for (final field in item.fields) ...[
                Text(
                  field.name == 'text'
                      ? l10n.structuredCompareFieldText
                      : l10n.structuredCompareFieldRuns,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (field.before is String && field.after is String)
                  StructuredComparisonTextSummary(
                    before: field.before as String,
                    after: field.after as String,
                  ),
                StructuredComparisonValue(
                  label: l10n.structuredCompareBefore,
                  present: field.beforePresent,
                  value: field.before,
                ),
                StructuredComparisonValue(
                  label: l10n.structuredCompareAfter,
                  present: field.afterPresent,
                  value: field.after,
                ),
              ],
            ],
          ),
      ],
    );
  }
}
