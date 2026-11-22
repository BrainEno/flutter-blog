import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/features/blog/domain/notion_import/notion_page_selection.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_messages.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

// The Notion import sheet's display pieces. They hold no state: the sheet
// owns the source, the selection, the plan and the network calls, and
// passes what to show and what to call back.

/// A page's name in the selection, or its number when it has no title.
String notionPageName(AppLocalizations l10n, NotionBundle source, int index) =>
    source.pageTitle(index).isEmpty
    ? l10n.notionImportUntitledPage(index + 1)
    : source.pageTitle(index);

/// The pages to import, each with a checkbox; a page and its translation
/// are ticked together. Ends with the preview button.
class NotionImportPageList extends StatelessWidget {
  const NotionImportPageList({
    super.key,
    required this.source,
    required this.selection,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.onPreview,
  });

  final NotionBundle source;
  final NotionPageSelection selection;
  final Set<int> selected;

  /// False while a request is in flight: nothing can change then.
  final bool enabled;
  final ValueChanged<Set<int>> onChanged;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pageCount = source.pageCount;
    final images = selection.imagesOf(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.notionImportSelectionTitle,
          style: theme.textTheme.titleMedium,
        ),
        Text(l10n.notionImportSelectionHint),
        Text(l10n.notionImportSelectionCount(selected.length, pageCount)),
        if (pageCount == 0) Text(l10n.notionImportNoPages),
        if (pageCount > 0) ...[
          Wrap(
            spacing: NoWaveSpacing.small,
            children: [
              TextButton(
                onPressed: !enabled || selected.length == pageCount
                    ? null
                    : () => onChanged(selection.all),
                child: Text(l10n.notionImportSelectAll),
              ),
              TextButton(
                onPressed: !enabled || selected.isEmpty
                    ? null
                    : () => onChanged({}),
                child: Text(l10n.notionImportClearSelection),
              ),
            ],
          ),
          for (var index = 0; index < pageCount; index++)
            CheckboxListTile(
              value: selected.contains(index),
              onChanged: !enabled
                  ? null
                  : (value) => onChanged(
                      selection.toggle(selected, index, include: value == true),
                    ),
              title: Text(
                notionPageName(l10n, source, index),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_subtitle(l10n, index)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: NoWaveSpacing.small),
            child: Text(
              l10n.notionImportImagesNote(images.length),
              key: const ValueKey('notion-import-images'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        FilledButton(
          onPressed: !enabled || selected.isEmpty ? null : onPreview,
          child: Text(l10n.notionImportPreviewSelected),
        ),
      ],
    );
  }

  String _subtitle(AppLocalizations l10n, int index) {
    final partners = selection.partnersOf(index);
    if (partners.isEmpty) return l10n.notionImportPageNumber(index + 1);
    return l10n.notionImportPagePaired(
      index + 1,
      partners.map((j) => notionPageName(l10n, source, j)).join(', '),
    );
  }
}

/// A preview's plan or an import's result: the counts, then each page with
/// what happened to it. [landed] adds, under an applied page, where it can
/// be found now.
class NotionImportReportView extends StatelessWidget {
  const NotionImportReportView({
    super.key,
    required this.report,
    required this.landed,
  });

  final NotionImportReport report;
  final List<Widget> Function(NotionImportPage page) landed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          report.applied ? l10n.notionImportResult : l10n.notionImportPlan,
          style: theme.textTheme.titleMedium,
        ),
        Text(
          l10n.notionImportSummary(
            report.count(NotionImportAction.create),
            report.count(NotionImportAction.update),
            report.count(NotionImportAction.skip),
            report.count(NotionImportAction.refused),
            report.count(NotionImportAction.failed),
          ),
        ),
        if (report.omittedPages > 0)
          Text(l10n.notionImportOmitted(report.omittedPages)),
        for (final page in report.pages) ...[
          const Divider(),
          Text(
            '${notionActionLabel(l10n, page.action)} · '
            '${page.title} (${page.locale})',
            style: theme.textTheme.titleSmall,
          ),
          if (page.detail.isNotEmpty) Text(page.detail),
          if (page.slug.isNotEmpty)
            Text('${l10n.notionImportSlug}: ${page.slug}'),
          if (report.applied) ...landed(page),
          NotionReportIssues(issues: page.issues),
        ],
      ],
    );
  }
}

/// The conversion's warnings, one line per kind: a 200-page export that
/// lacks page IDs says so once, with a count and the first few files, not
/// two hundred times.
class NotionConversionWarnings extends StatelessWidget {
  const NotionConversionWarnings({super.key, required this.warnings});

  final List<NotionMarkdownWarning> warnings;

  static const _namedFiles = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groups =
        <(NotionMarkdownWarningKind, String, String), List<String>>{};
    for (final warning in warnings) {
      groups
          .putIfAbsent((warning.kind, warning.detail, warning.table), () => [])
          .add(warning.source);
    }
    return Column(
      key: const ValueKey('notion-import-warnings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.notionImportWarningsTitle(warnings.length),
          style: theme.textTheme.titleSmall,
        ),
        for (final MapEntry(key: (kind, detail, table), value: sources)
            in groups.entries) ...[
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            sources.length > 1
                ? '${notionWarningMessage(l10n, kind, detail, table)} '
                      '(${l10n.notionImportWarningCount(sources.length)})'
                : notionWarningMessage(l10n, kind, detail, table),
          ),
          Text(
            _sources(l10n, sources),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  static String _sources(AppLocalizations l10n, List<String> sources) {
    final unique = sources.toSet().toList();
    final named = unique.take(_namedFiles).join(', ');
    return unique.length > _namedFiles
        ? l10n.notionImportWarningSources(named, unique.length - _namedFiles)
        : named;
  }
}

/// A page's report issues in words, one line per kind with a count. The
/// server's detail - a block type, a property - follows in small print; the
/// detail of an expiring image is its signed address and is never shown.
class NotionReportIssues extends StatelessWidget {
  const NotionReportIssues({super.key, required this.issues});

  final List<NotionImportIssue> issues;

  static const _namedDetails = 3;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groups = <String, List<String>>{};
    for (final issue in issues) {
      final details = groups.putIfAbsent(issue.code, () => []);
      final detail = issue.detail.trim();
      if (issue.code != 'expiring-image-url' && detail.isNotEmpty) {
        details.add(detail);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final MapEntry(key: code, value: details) in groups.entries) ...[
          Text(
            _counted(l10n, code, issues.where((i) => i.code == code).length),
          ),
          if (details.isNotEmpty)
            Text(
              details.toSet().take(_namedDetails).join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ],
    );
  }

  static String _counted(AppLocalizations l10n, String code, int count) {
    final message = notionIssueMessage(l10n, code);
    return count > 1
        ? '$message (${l10n.notionImportWarningCount(count)})'
        : message;
  }
}
