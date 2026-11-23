import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Result of an explicit article-conflict review.
///
/// A rebase means that the author has seen the server's currently returned
/// article and intentionally wants their still-local text to be guarded by
/// that response's revision. It never writes remotely and it never merges or
/// replaces local text automatically.
enum ArticleConflictReviewChoice { keepDraft, rebase }

/// Shows a three-way, read-only comparison after a conditional article write
/// conflicted. The editor passes the response it opened with, the durable local
/// draft, and a newly fetched server response. Keeping these values separate
/// matters: putting a fresh response straight into the text controllers would
/// make it look as though the user's draft had been resolved or merged.
Future<ArticleConflictReviewChoice?> showArticleConflictReviewSheet(
  BuildContext context, {
  required Blog openedArticle,
  required BlogDraft localDraft,
  required Blog latestArticle,
}) {
  return showModalBottomSheet<ArticleConflictReviewChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ArticleConflictReviewSheet(
      openedArticle: openedArticle,
      localDraft: localDraft,
      latestArticle: latestArticle,
    ),
  );
}

class _ArticleConflictReviewSheet extends StatelessWidget {
  const _ArticleConflictReviewSheet({
    required this.openedArticle,
    required this.localDraft,
    required this.latestArticle,
  });

  final Blog openedArticle;
  final BlogDraft localDraft;
  final Blog latestArticle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canRebase = latestArticle.authoringRevision != null;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      minChildSize: .46,
      maxChildSize: .96,
      builder: (context, controller) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: NoWaveSpacing.small),
              Container(
                height: 4,
                width: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(NoWaveRadius.pill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NoWaveSpacing.large,
                  NoWaveSpacing.medium,
                  NoWaveSpacing.small,
                  NoWaveSpacing.small,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.articleConflictReviewTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.articleConflictClose,
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(ArticleConflictReviewChoice.keepDraft),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NoWaveSpacing.large,
                  ),
                  children: [
                    Text(
                      l10n.articleConflictReviewBody,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: NoWaveSpacing.medium),
                    _RevisionSummary(
                      openedArticle: openedArticle,
                      localDraft: localDraft,
                      latestArticle: latestArticle,
                    ),
                    const SizedBox(height: NoWaveSpacing.large),
                    _ConflictField(
                      icon: Icons.title,
                      label: l10n.articleConflictTitleField,
                      opened: openedArticle.title,
                      local: localDraft.title,
                      latest: latestArticle.title,
                    ),
                    _ConflictField(
                      icon: Icons.subject,
                      label: l10n.articleConflictBodyField,
                      // Compare what the editor shows, not the flattened
                      // reading text of a structured article.
                      opened:
                          openedArticle.editableBody?.markdown ??
                          openedArticle.content,
                      local: localDraft.content,
                      latest:
                          latestArticle.editableBody?.markdown ??
                          latestArticle.content,
                      expands: true,
                    ),
                    _ConflictField(
                      icon: Icons.sell_outlined,
                      label: l10n.articleConflictTagsField,
                      opened: _joined(
                        openedArticle.tags,
                        l10n.articleConflictNoTags,
                      ),
                      local: _joined(
                        localDraft.tags,
                        l10n.articleConflictNoTags,
                      ),
                      latest: _joined(
                        latestArticle.tags,
                        l10n.articleConflictNoTags,
                      ),
                    ),
                    _ConflictField(
                      icon: Icons.folder_outlined,
                      label: l10n.articleConflictCategoriesField,
                      opened: _joined(
                        openedArticle.categoryIds,
                        l10n.articleConflictNoCategories,
                      ),
                      // A null category choice means the editor preserves what
                      // was opened; show that value instead of falsely saying
                      // the draft explicitly removed every category.
                      local: _joined(
                        localDraft.categoryIds ?? openedArticle.categoryIds,
                        l10n.articleConflictNoCategories,
                      ),
                      latest: _joined(
                        latestArticle.categoryIds,
                        l10n.articleConflictNoCategories,
                      ),
                    ),
                    _ConflictField(
                      icon: Icons.image_outlined,
                      label: l10n.articleConflictCoverField,
                      opened: _cover(openedArticle.imageUrl, l10n),
                      local: _cover(openedArticle.imageUrl, l10n),
                      latest: _cover(latestArticle.imageUrl, l10n),
                    ),
                    const SizedBox(height: NoWaveSpacing.medium),
                    Text(
                      l10n.articleConflictRebaseBody,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!canRebase)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: NoWaveSpacing.small,
                        ),
                        child: Text(
                          l10n.articleConflictMissingRevision,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: NoWaveSpacing.large),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.large),
                child: Row(
                  children: [
                    Expanded(
                      child: NoWaveButton(
                        label: l10n.articleConflictKeepDraft,
                        variant: NoWaveButtonVariant.quiet,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(ArticleConflictReviewChoice.keepDraft),
                      ),
                    ),
                    const SizedBox(width: NoWaveSpacing.medium),
                    Expanded(
                      child: NoWaveButton(
                        label: l10n.articleConflictRebase,
                        onPressed: canRebase
                            ? () => Navigator.of(
                                context,
                              ).pop(ArticleConflictReviewChoice.rebase)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _joined(List<String> values, String empty) =>
      values.isEmpty ? empty : values.join(', ');

  static String _cover(String value, AppLocalizations l10n) =>
      value.trim().isEmpty ? l10n.articleConflictNoCover : value;
}

class _RevisionSummary extends StatelessWidget {
  const _RevisionSummary({
    required this.openedArticle,
    required this.localDraft,
    required this.latestArticle,
  });

  final Blog openedArticle;
  final BlogDraft localDraft;
  final Blog latestArticle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(NoWaveRadius.none),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RevisionLine(
                label: l10n.articleConflictOriginal,
                value: openedArticle.authoringRevision?.value ?? '—',
              ),
              _RevisionLine(
                label: l10n.articleConflictLocal,
                value: localDraft.expectedRevision?.value ?? '—',
              ),
              _RevisionLine(
                label: l10n.articleConflictLatest,
                value: latestArticle.authoringRevision?.value ?? '—',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevisionLine extends StatelessWidget {
  const _RevisionLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.xs),
    child: Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
  );
}

class _ConflictField extends StatelessWidget {
  const _ConflictField({
    required this.icon,
    required this.label,
    required this.opened,
    required this.local,
    required this.latest,
    this.expands = false,
  });

  final IconData icon;
  final String label;
  final String opened;
  final String local;
  final String latest;
  final bool expands;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localChanged = local != opened;
    final latestChanged = latest != opened;
    final agrees = local == latest;
    final status = agrees
        ? l10n.articleConflictSame
        : l10n.articleConflictChanged;
    final statusColor = agrees
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: NoWaveSpacing.small),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Semantics(
                  label: status,
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NoWaveSpacing.small),
            _ComparisonValue(
              label: l10n.articleConflictOriginal,
              value: opened,
              changed: false,
              expands: expands,
            ),
            _ComparisonValue(
              label: l10n.articleConflictLocal,
              value: local,
              changed: localChanged,
              expands: expands,
            ),
            _ComparisonValue(
              label: l10n.articleConflictLatest,
              value: latest,
              changed: latestChanged,
              expands: expands,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonValue extends StatelessWidget {
  const _ComparisonValue({
    required this.label,
    required this.value,
    required this.changed,
    required this.expands,
  });

  final String label;
  final String value;
  final bool changed;
  final bool expands;

  @override
  Widget build(BuildContext context) {
    final maximumLines = expands ? 9 : 3;
    final color = changed
        ? Theme.of(context).colorScheme.tertiaryContainer
        : Colors.transparent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: NoWaveSpacing.small),
      padding: const EdgeInsets.all(NoWaveSpacing.small),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(NoWaveRadius.none),
      ),
      child: SelectableText(
        '$label\n$value',
        maxLines: maximumLines,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
