/// Page sizes and row caps, in one place (#295).
///
/// Each value is either a page size the client asks the server or the local
/// database for, or a cap that keeps an on-device store bounded. Ports
/// (repository and store interfaces) and their implementations read the same
/// constant, so a default can never drift between the two sides of an
/// override.
///
/// Server-side caps are mirrored, not decided, here: where a constant says it
/// matches the no-wave API, raising it requires the backend to raise its own
/// limit first.
abstract final class AppLimits {
  // --- Local stores -------------------------------------------------------

  /// The most feed articles the offline cache keeps and returns in one read.
  static const int blogCacheMaxRows = 500;

  /// One page of the structured-body recovery catalog.
  static const int structuredRecoveryPageSize = 25;

  /// The reading-history rows a single list read returns, newest first.
  static const int readingHistoryPageSize = 200;

  /// The searches the search page offers again, newest first.
  static const int recentSearches = 8;

  // --- Server pages -------------------------------------------------------

  /// One page of the notification inbox.
  static const int notificationPageSize = 50;

  /// The largest notification page the API accepts.
  static const int notificationMaxPageSize = 100;

  /// One page of the conversation list.
  static const int conversationPageSize = 50;

  /// One page of messages inside a conversation.
  static const int messagePageSize = 100;

  // --- Media ----------------------------------------------------------------

  /// The largest image `POST /me/media` accepts (no-wave REST limit at the
  /// audited upstream revision). The picker downsamples far below it, but a
  /// structured cover can carry a local file up to this size.
  static const int mediaUploadMaxBytes = 8 * 1024 * 1024;

  /// The weakest uplink the media upload budget is sized for: 1 Mbit/s, a
  /// congested or edge-of-coverage mobile connection. Used only to derive and
  /// test `AppDurations.mediaUploadTimeout`.
  static const int slowUplinkBytesPerSecond = 125000;

  /// The longest Notion import plan token accepted from a preview (#308): the
  /// no-wave limit of 512 KiB. A longer value is refused, never truncated.
  static const int notionImportPlanMaxTokenBytes = 512 * 1024;

  /// The most entries a Notion export ZIP may list, files and folders
  /// together, before the app refuses to read it. Mirrors the no-wave desk's
  /// own reader, so a ZIP the web refuses is refused here too.
  static const int notionZipMaxEntries = 2000;

  /// How deep a ZIP inside a ZIP is opened: Notion splits a large workspace
  /// export into part archives inside one outer archive.
  static const int notionZipMaxDepth = 1;

  /// The longest Markdown file name accepted as an article's identity when
  /// it carries no Notion page ID (the desk's limit).
  static const int notionMarkdownMaxFileName = 120;

  /// The longest code block the site keeps; longer ones are cut by the
  /// server, and the conversion says so first.
  static const int notionMarkdownMaxCodeChars = 50000;

  /// The most an author may choose at once for a Notion import, files
  /// together. Larger than one import request (8 MiB of JSON) because an
  /// export's images travel separately, one media upload each; the Markdown
  /// and CSV inside stay bounded by the request limit.
  static const int notionImportMaxSourceBytes = 64 * 1024 * 1024;

  /// The most images from an export one preview uploads. Each is a separate
  /// media upload sized for a slow uplink, so a larger selection is split by
  /// the author rather than left uploading for an hour.
  static const int notionImportMaxImages = 60;

  // --- Display ------------------------------------------------------------

  /// UTF-16 code units per page when a long structured value is shown in the
  /// conflict comparison view.
  static const int structuredComparisonPageSize = 1000;

  /// Characters (code points) of body text a list row shows under a title
  /// when the article has no excerpt of its own.
  static const int articleExcerptCharacters = 150;
}
