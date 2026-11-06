/// One message in a private conversation (`conversations.messages`).
///
/// The server is the only writer: a message is immutable once stored, so there
/// is no local edit state and nothing to reconcile. [duplicate] is the server's
/// own answer to a replayed `Idempotency-Key` - the row already existed and the
/// retry did not create a second one.
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.duplicate = false,
  });

  final String id;
  final String conversationId;

  /// The account that sent it; compared with the viewer to pick a side.
  final String senderId;

  /// Plain text, exactly as the server stores it. Never rendered as markup.
  final String body;

  final DateTime createdAt;

  /// True when the server replayed an earlier write instead of storing a new
  /// message. The row is still the original message, not a second copy.
  final bool duplicate;

  bool sentBy(String? userId) => userId != null && userId == senderId;
}
