import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';

/// A list item has no persistent ID in the upstream schema. Rows compare the
/// same ordinal only: insertion or reordering may change many rows. This is
/// not an alignment, an edit script, or a merge decision.
final class StructuredListItemComparison {
  const StructuredListItemComparison({
    required this.index,
    required this.fields,
  });
  final int index;
  final List<StructuredFieldChange> fields;
  bool get changed => fields.isNotEmpty;
}

/// Compares list item text and optional inline runs without matching items by
/// text, which could wrongly identify duplicate items as the same object.
/// Only same-ID list blocks are eligible; other type changes remain visible
/// in the ordinary block comparison. Documents were validated at creation.
List<StructuredListItemComparison>? compareStructuredListItems(
  StructuredArticleDraft before,
  StructuredArticleDraft after,
  String blockId,
) {
  Map<String, Object?>? find(StructuredArticleDraft document) {
    for (final block in document.blocks) {
      if (block['id'] == blockId) return block;
    }
    return null;
  }

  final oldBlock = find(before);
  final newBlock = find(after);
  if (oldBlock == null ||
      newBlock == null ||
      oldBlock['type'] != 'list' ||
      newBlock['type'] != 'list') {
    return null;
  }
  final oldItems = oldBlock['items'] as List;
  final newItems = newBlock['items'] as List;
  final oldRuns = oldBlock['itemInlines'] as List?;
  final newRuns = newBlock['itemInlines'] as List?;
  final count = oldItems.length > newItems.length
      ? oldItems.length
      : newItems.length;
  final result = <StructuredListItemComparison>[];
  for (var index = 0; index < count; index++) {
    final oldPresent = index < oldItems.length;
    final newPresent = index < newItems.length;
    final fields = <StructuredFieldChange>[];
    final oldText = oldPresent ? oldItems[index] : null;
    final newText = newPresent ? newItems[index] : null;
    if (oldPresent != newPresent || oldText != newText) {
      fields.add(
        StructuredFieldChange(
          name: 'text',
          beforePresent: oldPresent,
          before: oldText,
          afterPresent: newPresent,
          after: newText,
        ),
      );
    }
    final oldRunsPresent = oldPresent && oldRuns != null;
    final newRunsPresent = newPresent && newRuns != null;
    final oldValue = oldRunsPresent ? oldRuns[index] : null;
    final newValue = newRunsPresent ? newRuns[index] : null;
    if (oldRunsPresent != newRunsPresent ||
        !structuredComparisonJsonEquals(oldValue, newValue)) {
      fields.add(
        StructuredFieldChange(
          name: 'inlines',
          beforePresent: oldRunsPresent,
          before: oldValue,
          afterPresent: newRunsPresent,
          after: newValue,
        ),
      );
    }
    result.add(
      StructuredListItemComparison(
        index: index,
        fields: List.unmodifiable(fields),
      ),
    );
  }
  return List.unmodifiable(result);
}
