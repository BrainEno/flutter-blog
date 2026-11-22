import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/transport/api_error.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/l10n/app_localizations.dart';

// The Notion import's words, kept apart from its widgets: each function maps
// one domain value to a localized message, so a new code or warning kind is
// a one-line change here.

/// A 429 is refused before any work, so even an apply is known not to have
/// landed. The server's Retry-After, when sent, says how long to wait.
String notionRateLimitedMessage(AppLocalizations l10n, Failure failure) {
  final cause = failure.cause;
  final seconds = cause is NowaveApiException ? cause.retryAfterSeconds : null;
  if (seconds == null || seconds <= 0) return l10n.notionImportRateLimited;
  return l10n.notionImportRateLimitedRetry(
    (seconds / Duration.secondsPerMinute).ceil(),
  );
}

/// The words for a file or text that cannot be read as an import source.
String notionSourceErrorMessage(
  AppLocalizations l10n,
  NotionImportSourceException error,
) {
  final name = error.name.isEmpty ? l10n.notionImportChosenFile : error.name;
  return switch (error.error) {
    NotionImportSourceError.tooLarge => l10n.notionImportSourceTooLarge,
    NotionImportSourceError.unsupportedFile =>
      l10n.notionImportSourceUnsupported(name),
    NotionImportSourceError.invalidBundle =>
      l10n.notionImportSourceInvalidBundle(name),
    NotionImportSourceError.invalidZip => l10n.notionImportSourceInvalidZip(
      name,
    ),
    NotionImportSourceError.tooManyEntries =>
      l10n.notionImportSourceTooManyEntries(name),
    NotionImportSourceError.tooManyPages => l10n.notionImportSourceTooManyPages,
    NotionImportSourceError.invalidText => l10n.notionImportSourceInvalidText(
      name,
    ),
    NotionImportSourceError.duplicatePage => l10n.notionImportSourceDuplicate(
      name,
    ),
    NotionImportSourceError.noPages => l10n.notionImportSourceNoPages,
    NotionImportSourceError.csvOnly => l10n.notionImportSourceCsvOnly,
  };
}

/// The label for what the server did, or would do, with a page.
String notionActionLabel(AppLocalizations l10n, NotionImportAction action) =>
    switch (action) {
      NotionImportAction.create => l10n.notionImportCreate,
      NotionImportAction.update => l10n.notionImportUpdate,
      NotionImportAction.skip => l10n.notionImportSkip,
      NotionImportAction.refused => l10n.notionImportRefused,
      NotionImportAction.failed => l10n.notionImportFailed,
    };

/// The words for a conversion warning.
String notionWarningMessage(
  AppLocalizations l10n,
  NotionMarkdownWarningKind kind,
  String detail,
  String table,
) => switch (kind) {
  NotionMarkdownWarningKind.missingTitle => l10n.notionImportWarnMissingTitle,
  NotionMarkdownWarningKind.invalidFileName =>
    l10n.notionImportWarnInvalidFileName,
  NotionMarkdownWarningKind.fileNameIdentity =>
    l10n.notionImportWarnFileNameIdentity,
  NotionMarkdownWarningKind.pastedIdentity =>
    l10n.notionImportWarnPastedIdentity,
  NotionMarkdownWarningKind.propertyIgnored =>
    l10n.notionImportWarnPropertyIgnored(detail),
  NotionMarkdownWarningKind.publishedUnrecognized =>
    l10n.notionImportWarnPublished,
  NotionMarkdownWarningKind.titleFromFileName =>
    l10n.notionImportWarnTitleFromFileName(detail),
  NotionMarkdownWarningKind.dateUnrecognized =>
    detail.isEmpty
        ? l10n.notionImportWarnDate
        : l10n.notionImportWarnCsvDate(detail),
  NotionMarkdownWarningKind.dateRange => l10n.notionImportWarnDateRange,
  NotionMarkdownWarningKind.relationUnrecognized =>
    l10n.notionImportWarnRelationUnrecognized(detail),
  NotionMarkdownWarningKind.relationMissing =>
    l10n.notionImportWarnRelationMissing(detail),
  NotionMarkdownWarningKind.inlineImageDropped =>
    l10n.notionImportWarnInlineImage,
  NotionMarkdownWarningKind.relativeLinkDropped =>
    l10n.notionImportWarnRelativeLink,
  NotionMarkdownWarningKind.headingLowered => l10n.notionImportWarnHeading,
  NotionMarkdownWarningKind.codeTooLong => l10n.notionImportWarnCode,
  NotionMarkdownWarningKind.localImageMissing =>
    l10n.notionImportWarnImageMissing(detail),
  NotionMarkdownWarningKind.localImageUnsupported =>
    l10n.notionImportWarnImageUnsupported(detail),
  NotionMarkdownWarningKind.localImageTooLarge =>
    l10n.notionImportWarnImageTooLarge(detail),
  NotionMarkdownWarningKind.signedImageDropped =>
    l10n.notionImportWarnSignedImage,
  NotionMarkdownWarningKind.listSimplified => l10n.notionImportWarnList,
  NotionMarkdownWarningKind.tableFlattened => l10n.notionImportWarnTable,
  NotionMarkdownWarningKind.otherFlattened => l10n.notionImportWarnOther,
  NotionMarkdownWarningKind.csvColumnsIgnored =>
    l10n.notionImportWarnCsvColumns(table, detail),
  NotionMarkdownWarningKind.csvPublishedNotCheckbox =>
    l10n.notionImportWarnCsvPublished(table, detail),
  NotionMarkdownWarningKind.csvNoRow => l10n.notionImportWarnCsvNoRow,
  NotionMarkdownWarningKind.csvAmbiguousRow =>
    l10n.notionImportWarnCsvAmbiguous(detail),
  NotionMarkdownWarningKind.csvFilled => l10n.notionImportWarnCsvFilled(
    table,
    detail,
  ),
  NotionMarkdownWarningKind.csvNothingToFill => l10n.notionImportWarnCsvNothing(
    table,
  ),
  NotionMarkdownWarningKind.csvLocalCover => l10n.notionImportWarnCsvLocalCover,
};

/// The words for a server issue code; an unknown code is named, not hidden.
String notionIssueMessage(AppLocalizations l10n, String code) => switch (code) {
  'slug-derived' => l10n.notionImportIssueSlugDerived,
  'empty-block-dropped' => l10n.notionImportIssueEmptyBlock,
  'expiring-image-url' => l10n.notionImportIssueExpiringImage,
  'featured-image-not-carried' => l10n.notionImportIssueFeaturedImage,
  'hierarchy-not-carried' => l10n.notionImportIssueHierarchy,
  'work-type-fallback' => l10n.notionImportIssueWorkTypeFallback,
  'link-block-flattened' => l10n.notionImportIssueLinkBlock,
  'equation-flattened' => l10n.notionImportIssueEquation,
  'callout-flattened' => l10n.notionImportIssueCallout,
  'toggle-flattened' => l10n.notionImportIssueToggle,
  'checkbox-state-dropped' => l10n.notionImportIssueCheckbox,
  'table-block-dropped' => l10n.notionImportIssueTable,
  'unsupported-block' => l10n.notionImportIssueUnsupportedBlock,
  'invalid-block-dropped' => l10n.notionImportIssueInvalidBlock,
  'empty-title' => l10n.notionImportIssueEmptyTitle,
  'empty-body' => l10n.notionImportIssueEmptyBody,
  'image-copy-failed' => l10n.notionImportIssueImageCopyFailed,
  'translation-locale-not-carried' => l10n.notionImportIssueTranslationLocale,
  'work-type-not-carried' => l10n.notionImportIssueWorkType,
  _ => l10n.notionImportIssueOther(code),
};
