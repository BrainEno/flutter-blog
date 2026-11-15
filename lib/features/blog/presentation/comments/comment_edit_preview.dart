import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// An in-memory review of the exact text this dialog is about to replace.
/// This compares the local snapshot, not a freshly fetched server version;
/// another device may still have edited it since the snapshot was loaded.
class CommentEditPreview extends StatelessWidget {
  const CommentEditPreview({
    super.key,
    required this.original,
    required this.draft,
  });

  final String original;
  final String draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: NoWaveSpacing.small),
      title: Text(context.l10n.commentEditReview),
      subtitle: Text(context.l10n.commentEditReviewExplanation),
      children: [
        _ReviewText(
          label: context.l10n.commentEditOriginal,
          text: original,
          background: theme.colorScheme.surfaceContainerHighest,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        _ReviewText(
          label: context.l10n.commentEditDraft,
          text: draft.trim(),
          background: theme.colorScheme.primaryContainer,
        ),
      ],
    );
  }
}

class _ReviewText extends StatelessWidget {
  const _ReviewText({
    required this.label,
    required this.text,
    required this.background,
  });

  final String label;
  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NoWaveSpacing.small),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(NoWaveRadius.none),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: NoWaveSpacing.xs),
          SelectableText(text),
        ],
      ),
    );
  }
}
