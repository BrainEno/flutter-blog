import 'package:belog/features/messages/domain/entities/conversation_message.dart';

/// One conversation as one of its members sees it (`conversations`).
///
/// The server does not include participant names or avatars: `participantIds`
/// are the identities, and the app resolves the names separately. Treating the
/// ids as the truth and the names as a decoration keeps a failed name lookup
/// from looking like a conversation with nobody in it.
class Conversation {
  const Conversation({
    required this.id,
    required this.participantIds,
    required this.unreadCount,
    this.createdBy,
    this.createdAt,
    this.lastActivityAt,
    this.lastMessage,
  });

  final String id;

  /// Every active member, including the viewer. An empty list stays empty
  /// here rather than being invented.
  final List<String> participantIds;

  /// How many messages *this* member has not read yet. `0` is a real answer.
  final int unreadCount;

  /// The member who opened the conversation; only that member may change the
  /// participant list (a capability this build does not use yet).
  final String? createdBy;

  final DateTime? createdAt;

  /// When the newest message arrived (or when the conversation was created).
  final DateTime? lastActivityAt;

  final ConversationMessage? lastMessage;

  /// Everyone except [viewerId], in the order the server listed them.
  List<String> others(String? viewerId) {
    if (viewerId == null) return participantIds;
    return [
      for (final id in participantIds)
        if (id != viewerId) id,
    ];
  }

  /// The newest thing that happened here, used for the row's timestamp.
  DateTime? get lastEventAt => lastMessage?.createdAt ?? lastActivityAt;

  Conversation copyWith({int? unreadCount}) {
    return Conversation(
      id: id,
      participantIds: participantIds,
      unreadCount: unreadCount ?? this.unreadCount,
      createdBy: createdBy,
      createdAt: createdAt,
      lastActivityAt: lastActivityAt,
      lastMessage: lastMessage,
    );
  }
}
