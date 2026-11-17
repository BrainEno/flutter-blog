import 'dart:convert';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison_text.dart';
import 'package:flutter/material.dart';

/// Displays one exact JSON value in bounded, user-navigable chunks. Paged
/// display keeps large code blocks and list fields inspectable without loading
/// a huge paragraph into the text layout engine. This is not an export.
class StructuredComparisonValue extends StatefulWidget {
  const StructuredComparisonValue({
    super.key,
    required this.label,
    required this.present,
    required this.value,
  });
  final String label;
  final bool present;
  final Object? value;

  @override
  State<StructuredComparisonValue> createState() =>
      _StructuredComparisonValueState();
}

class _StructuredComparisonValueState extends State<StructuredComparisonValue> {
  StructuredValuePages? _pages;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StructuredComparisonValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.present != widget.present ||
        !identical(oldWidget.value, widget.value)) {
      _load();
    }
  }

  void _load() {
    _index = 0;
    _pages = widget.present
        ? StructuredValuePages.create(jsonEncode(widget.value))
        : null;
  }

  @override
  void dispose() {
    _pages = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!widget.present) {
      return Text('${widget.label}: ${l10n.structuredCompareAbsent}');
    }
    final pages = _pages;
    if (pages == null) {
      return Text('${widget.label}: ${l10n.structuredCompareInvalidText}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        SelectableText(pages.page(_index)),
        if (pages.length > 1) ...[
          Text(l10n.structuredComparePagedValue),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _index == 0 ? null : () => setState(() => _index--),
                icon: const Icon(Icons.chevron_left),
                label: Text(l10n.structuredComparePrevious),
              ),
              Text('${_index + 1} / ${pages.length}'),
              TextButton.icon(
                onPressed: _index + 1 >= pages.length
                    ? null
                    : () => setState(() => _index++),
                icon: const Icon(Icons.chevron_right),
                label: Text(l10n.structuredCompareNext),
              ),
            ],
          ),
        ],
        const SizedBox(height: NoWaveSpacing.small),
      ],
    );
  }
}

/// Supplementary plain-text summary for changed string fields. Full exact JSON
/// values remain available separately, including optional field presence.
class StructuredComparisonTextSummary extends StatelessWidget {
  const StructuredComparisonTextSummary({
    super.key,
    required this.before,
    required this.after,
  });
  final String before;
  final String after;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final change = StructuredTextChange.between(before, after);
    if (change == null || !change.changed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.structuredCompareTextSummary,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(l10n.structuredCompareTextSummaryNote),
        StructuredComparisonValue(
          label: l10n.structuredCompareBeforeMiddle,
          present: true,
          value: change.beforeMiddle,
        ),
        StructuredComparisonValue(
          label: l10n.structuredCompareAfterMiddle,
          present: true,
          value: change.afterMiddle,
        ),
      ],
    );
  }
}
