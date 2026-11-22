import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:flutter/material.dart';

/// One block of the local structured editor: its type and position, the
/// row of actions it allows, and a plain preview of its content. It holds
/// no state; the editor page decides what is allowed and does the work.
class StructuredBlockCard extends StatelessWidget {
  const StructuredBlockCard({
    super.key,
    required this.block,
    required this.position,
    required this.editable,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
    required this.canInsert,
    required this.canBold,
    required this.canEditText,
    required this.canEditInline,
    required this.onProperties,
    required this.onInsert,
    required this.onList,
    required this.onInline,
    required this.onText,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.onBold,
  });
  final Map<String, Object?> block;
  final int position;
  final bool editable;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;
  final bool canInsert;
  final bool canBold;
  final bool canEditText;
  final bool canEditInline;
  final VoidCallback onProperties;
  final VoidCallback onInsert;
  final VoidCallback onList;
  final VoidCallback onInline;
  final VoidCallback onText;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;
  final VoidCallback onBold;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = block['type'];
    final label = switch (type) {
      'paragraph' => l10n.structuredParagraph,
      'heading' => l10n.structuredHeading,
      'quote' => l10n.structuredQuote,
      'list' => l10n.structuredList,
      'image' => l10n.structuredImage,
      'code' => l10n.structuredCode,
      _ => l10n.structuredUnavailable,
    };
    final formatable = const {
      'paragraph',
      'heading',
      'quote',
      'list',
    }.contains(type);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.structuredBlock} $position: $label',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._preview(context),
            Wrap(
              children: [
                IconButton(
                  tooltip: l10n.structuredMoveUp,
                  onPressed: editable && canMoveUp ? onMoveUp : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: l10n.structuredMoveDown,
                  onPressed: editable && canMoveDown ? onMoveDown : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: l10n.structuredRemove,
                  onPressed: editable && canRemove ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: l10n.structuredInsertBlockAfter,
                  onPressed: editable && canInsert ? onInsert : null,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                if (type == 'list')
                  IconButton(
                    tooltip: l10n.structuredListOpen,
                    onPressed: editable ? onList : null,
                    icon: const Icon(Icons.format_list_bulleted),
                  ),
                if (const {
                  'image',
                  'code',
                  'quote',
                  'heading',
                  'list',
                }.contains(type))
                  IconButton(
                    tooltip: l10n.structuredPropertiesOpen,
                    onPressed: editable ? onProperties : null,
                    icon: const Icon(Icons.tune),
                  ),
                if (canEditText &&
                    const {'paragraph', 'heading', 'quote'}.contains(type) &&
                    !block.containsKey('inlines'))
                  IconButton(
                    tooltip: l10n.structuredTextOpen,
                    onPressed: editable ? onText : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (canEditInline &&
                    const {
                      'paragraph',
                      'heading',
                      'quote',
                      'list',
                    }.contains(type))
                  IconButton(
                    tooltip: l10n.structuredInlineOpen,
                    onPressed: editable ? onInline : null,
                    icon: const Icon(Icons.format_paint_outlined),
                  ),
                if (formatable && canBold)
                  IconButton(
                    tooltip: l10n.structuredBold,
                    isSelected: structuredFirstRunIsBold(block),
                    onPressed: editable ? onBold : null,
                    icon: const Icon(Icons.format_bold),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _preview(BuildContext context) {
    final l10n = context.l10n;
    String safe(String value) =>
        isWellFormedUtf16(value) ? value : l10n.structuredInlineUnsupported;
    switch (block['type']) {
      case 'paragraph':
      case 'heading':
      case 'quote':
        return [
          Text(safe(block['text'] as String)),
          if (block['attribution'] case final String attribution)
            Text('${l10n.structuredAttribution}: ${safe(attribution)}'),
        ];
      case 'list':
        return [
          for (final item in block['items'] as List)
            Text('• ${safe(item as String)}'),
        ];
      case 'image':
        return [
          Text(safe(block['src'] as String)),
          Text('${l10n.structuredAlt}: ${safe(block['alt'] as String)}'),
          if (block['caption'] case final String caption)
            Text('${l10n.structuredCaption}: ${safe(caption)}'),
        ];
      case 'code':
        return [
          Text(safe(block['language'] as String)),
          Text(safe(block['code'] as String)),
        ];
      default:
        return [];
    }
  }
}

/// A missing inline array means a single unformatted fallback run.
bool structuredFirstRunIsBold(Map<String, Object?> block) {
  final Object? runs = block['type'] == 'list'
      ? (block['itemInlines'] is List
            ? (block['itemInlines'] as List).first
            : null)
      : block['inlines'];
  if (runs is! List || runs.isEmpty || runs.first is! Map) return false;
  final marks = (runs.first as Map)['marks'];
  return marks is List && marks.contains('bold');
}
