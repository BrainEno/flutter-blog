// What converting a Notion Markdown export could not carry over exactly.
// The sheet groups these by kind and words them; see notion_import_messages.

/// Something the conversion could not carry exactly. The import still goes
/// ahead; the sheet lists these before the preview so nothing is lost
/// silently.
enum NotionMarkdownWarningKind {
  /// Skipped: no `# Title` and no file name to take one from.
  missingTitle,

  /// No `# Title`: the file name ([detail]) is the title.
  titleFromFileName,

  /// Skipped: no Notion page ID and an unusable file name.
  invalidFileName,

  /// No Notion page ID in the file name: identified by the name instead,
  /// so a renamed file imports as a new article.
  fileNameIdentity,

  /// Pasted: identified by its title, so a new title is a new article.
  pastedIdentity,

  /// A Notion property the site has no field for ([detail] names it).
  propertyIgnored,

  /// `Published` was neither yes nor no: treated as a draft.
  publishedUnrecognized,

  /// `Date` ([detail], when from a CSV) could not be read: the server's
  /// default applies.
  dateUnrecognized,

  /// `Date` is a range: only its start is kept.
  dateRange,

  /// `English` or `Parent item` ([detail]) named no page this reader knows.
  relationUnrecognized,

  /// `English` or `Parent item` ([detail]) points to a page not chosen.
  relationMissing,

  /// An image inside a line of text was left out.
  inlineImageDropped,

  /// A link to another page of the export, not a web address: the text
  /// stays, the link does not.
  relativeLinkDropped,

  /// A fourth-level or deeper heading was raised to the third level.
  headingLowered,

  /// A code block longer than the site keeps.
  codeTooLong,

  /// A local image ([detail] is its caption) that is not in the chosen
  /// files.
  localImageMissing,

  /// A local image ([detail]) in a format the site does not take.
  localImageUnsupported,

  /// A local image ([detail]) larger than one upload may be.
  localImageTooLarge,

  /// A signed image address that cannot be copied safely.
  signedImageDropped,

  /// A nested list or a list item with several paragraphs was flattened.
  listSimplified,

  /// A table became one paragraph per row.
  tableFlattened,

  /// A callout, HTML or other construct was kept as plain text.
  otherFlattened,

  /// Columns ([detail]) of a database CSV ([source]) with no article field.
  csvColumnsIgnored,

  /// A CSV's ([source]) Published column ([detail]) holds more than
  /// checkbox values, so it does not decide publication.
  csvPublishedNotCheckbox,

  /// No row of the database CSVs matches the page.
  csvNoRow,

  /// Several ([detail]) CSV rows match the page: none is used.
  csvAmbiguousRow,

  /// Empty properties ([detail]) were filled from a CSV ([table]).
  csvFilled,

  /// The page's CSV row ([table]) had nothing the Markdown lacked.
  csvNothingToFill,

  /// The CSV cover is a file inside the export, not an address.
  csvLocalCover,
}

class NotionMarkdownWarning {
  const NotionMarkdownWarning(
    this.kind,
    this.source, {
    this.detail = '',
    this.table = '',
  });

  final NotionMarkdownWarningKind kind;

  /// The file (or pasted title, or CSV) it is about.
  final String source;
  final String detail;

  /// The database CSV involved, for the CSV kinds that name one.
  final String table;
}
