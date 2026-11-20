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

  // --- Server pages -------------------------------------------------------

  /// One page of the notification inbox.
  static const int notificationPageSize = 50;

  /// The largest notification page the API accepts.
  static const int notificationMaxPageSize = 100;

  /// One page of the conversation list.
  static const int conversationPageSize = 50;

  /// One page of messages inside a conversation.
  static const int messagePageSize = 100;

  // --- Display ------------------------------------------------------------

  /// UTF-16 code units per page when a long structured value is shown in the
  /// conflict comparison view.
  static const int structuredComparisonPageSize = 1000;
}
