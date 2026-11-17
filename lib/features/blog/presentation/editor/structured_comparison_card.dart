import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison_list.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_list.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_value.dart';
import 'package:flutter/material.dart';

/// A read-only row with lazy field details. Values are displayed as inert JSON,
/// preserving optional-field absence and whitespace rather than rendering
/// Markdown or following links. Large values are shown in bounded pages.
class StructuredComparisonCard extends StatelessWidget {
  const StructuredComparisonCard({
    super.key,
    required this.change,
    required this.comparison,
  });
  final StructuredBlockChange change;
  final StructuredDocumentComparison comparison;

  String _type(BuildContext context, String? type) {
    final l10n = context.l10n;
    return switch (type) {
      'paragraph' => l10n.structuredParagraph,
      'heading' => l10n.structuredHeading,
      'quote' => l10n.structuredQuote,
      'list' => l10n.structuredList,
      'image' => l10n.structuredImage,
      'code' => l10n.structuredCode,
      null => l10n.structuredCompareAbsent,
      _ => l10n.structuredUnavailable,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final before = change.beforeIndex;
    final after = change.afterIndex;
    final id = isWellFormedUtf16(change.id)
        ? change.id
        : l10n.structuredInlineUnsupported;
    final flags = <String>[
      if (change.added) l10n.structuredCompareAdded,
      if (change.removed) l10n.structuredCompareRemoved,
      if (change.moved) l10n.structuredCompareMoved,
      if (change.modified) l10n.structuredCompareModified,
      if (!change.changed) l10n.structuredCompareUnchanged,
    ];
    return Card(
      child: ExpansionTile(
        title: Text(
          '${_type(context, change.afterType ?? change.beforeType)} · ${flags.join(' / ')}',
        ),
        subtitle: Text(
          '${l10n.structuredCompareBlockId}: $id\n'
          '${l10n.structuredCompareBeforePosition}: ${before == null ? l10n.structuredCompareAbsent : before + 1}\n'
          '${l10n.structuredCompareAfterPosition}: ${after == null ? l10n.structuredCompareAbsent : after + 1}',
        ),
        childrenPadding: const EdgeInsets.all(NoWaveSpacing.medium),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (change.moved) Text(l10n.structuredCompareMoveExplanation),
          if (change.fields.isEmpty) Text(l10n.structuredCompareNoFields),
          if (compareStructuredListItems(
                comparison.before,
                comparison.after,
                change.id,
              )
              case final items?)
            StructuredComparisonList(items: items),
          for (final field in change.fields) _FieldComparison(field: field),
        ],
      ),
    );
  }
}

class _FieldComparison extends StatelessWidget {
  const _FieldComparison({required this.field});
  final StructuredFieldChange field;

  String _label(BuildContext context) {
    final l10n = context.l10n;
    return switch (field.name) {
      'type' => l10n.structuredCompareFieldType,
      'text' => l10n.structuredCompareFieldText,
      'inlines' => l10n.structuredCompareFieldRuns,
      'level' => l10n.structuredPropertiesLevel,
      'attribution' => l10n.structuredPropertiesAttribution,
      'ordered' => l10n.structuredPropertiesOrdered,
      'items' => l10n.structuredCompareFieldItems,
      'itemInlines' => l10n.structuredCompareFieldItemRuns,
      'src' => l10n.structuredInsertImageUrl,
      'alt' => l10n.structuredPropertiesAlt,
      'caption' => l10n.structuredPropertiesCaption,
      'language' => l10n.structuredPropertiesLanguage,
      'code' => l10n.structuredPropertiesCode,
      _ => l10n.structuredCompareUnknownField,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: NoWaveSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label(context), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: NoWaveSpacing.small),
          if (field.beforePresent &&
              field.afterPresent &&
              field.before is String &&
              field.after is String)
            StructuredComparisonTextSummary(
              before: field.before as String,
              after: field.after as String,
            ),
          StructuredComparisonValue(
            label: l10n.structuredCompareBefore,
            present: field.beforePresent,
            value: field.before,
          ),
          const SizedBox(height: NoWaveSpacing.small),
          StructuredComparisonValue(
            label: l10n.structuredCompareAfter,
            present: field.afterPresent,
            value: field.after,
          ),
        ],
      ),
    );
  }
}
