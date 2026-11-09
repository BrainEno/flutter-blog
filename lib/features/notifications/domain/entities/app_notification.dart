/// What a notification is about, as far as this build can tell.
///
/// The server sends an opaque `payload` JSON string next to a stable
/// `eventKey`. Only the shapes listed here are understood; everything else is
/// [unknown] and still shown, because "something happened" is more useful than
/// an empty row the reader cannot see.
enum AppNotificationKind {
  /// The author deleted a work this user commented on. The comments go with
  /// it, and [AppNotification.purgesAt] is the date the sweep runs.
  articleDeleted,

  /// Another participant sent a private message. The inbox offers a link to
  /// the conversation when the notification includes its id.
  messageReceived,

  /// An event type this build does not know (or a payload it cannot read).
  unknown,
}

/// One notification from the account's inbox.
///
/// The inbox is read-only server state: the list is the only source, the unread
/// count is derived from it, and marking read is the only write. No part of it
/// is cached, persisted or logged.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventKey,
    required this.kind,
    required this.createdAt,
    required this.readAt,
    this.articleId,
    this.purgesAt,
    this.conversationId,
  });

  /// Server identifier; the only value `PUT .../read` accepts.
  final String id;

  /// The server's deduplication key for the event that produced this row.
  final String eventKey;

  final AppNotificationKind kind;
  final DateTime createdAt;

  /// Null while the notification is unread.
  final DateTime? readAt;

  /// Set for [AppNotificationKind.articleDeleted].
  final String? articleId;

  /// Set for [AppNotificationKind.articleDeleted] when the server named a date.
  final DateTime? purgesAt;

  /// Set for [AppNotificationKind.messageReceived].
  final String? conversationId;

  bool get isRead => readAt != null;

  /// The same notification, read. Keeps the first read instant if the server
  /// already set one, so a repeated mark cannot rewrite history.
  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    eventKey: eventKey,
    kind: kind,
    createdAt: createdAt,
    readAt: readAt ?? at,
    articleId: articleId,
    purgesAt: purgesAt,
    conversationId: conversationId,
  );
}
