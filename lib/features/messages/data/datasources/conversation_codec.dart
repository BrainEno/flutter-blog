import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';

/// Parses one serialized `conversations` row.
///
/// The envelope is strict: an id, a participant list, an unread count and any
/// timestamp the row carries must be readable, or the row throws
/// [FormatException]. A conversation the app half-understands is worse than a
/// failed read: it would show a count it made up or a member list it guessed.
/// Optional fields (`createdAt`, `lastActivityAt`, `lastMessage`) may be
/// absent, but a present one that cannot be parsed is still an error.
Conversation conversationFromRow(Object? row) {
  if (row is! Map<String, dynamic>) {
    throw const FormatException('Invalid conversation row');
  }
  final id = row['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Invalid conversation id');
  }
  final participants = row['participantIds'];
  if (participants is! List) {
    throw const FormatException('Invalid conversation participants');
  }
  final participantIds = <String>[];
  for (final entry in participants) {
    if (entry is! String || entry.isEmpty) {
      throw const FormatException('Invalid conversation participant');
    }
    participantIds.add(entry);
  }
  final unread = row['unreadCount'];
  if (unread is! int || unread < 0) {
    throw const FormatException('Invalid conversation unread count');
  }
  final createdBy = row['createdBy'];
  if (createdBy != null && createdBy is! String) {
    throw const FormatException('Invalid conversation creator');
  }
  final lastMessage = row['lastMessage'];
  return Conversation(
    id: id,
    participantIds: List.unmodifiable(participantIds),
    unreadCount: unread,
    createdBy: createdBy as String?,
    createdAt: optionalTime(row['createdAt']),
    lastActivityAt: optionalTime(row['lastActivityAt']),
    lastMessage: lastMessage == null ? null : messageFromRow(lastMessage),
  );
}

/// Parses one serialized `conversations.messages` row.
ConversationMessage messageFromRow(Object? row) {
  if (row is! Map<String, dynamic>) {
    throw const FormatException('Invalid message row');
  }
  final id = row['id'];
  final conversationId = row['conversationId'];
  final senderId = row['senderId'];
  final body = row['body'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Invalid message id');
  }
  if (conversationId is! String || conversationId.isEmpty) {
    throw const FormatException('Invalid message conversation');
  }
  if (senderId is! String || senderId.isEmpty) {
    throw const FormatException('Invalid message sender');
  }
  if (body is! String) {
    throw const FormatException('Invalid message body');
  }
  return ConversationMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    body: body,
    createdAt: requiredTime(row['createdAt']),
    duplicate: row['duplicate'] == true,
  );
}

/// A timestamp the server sends as ISO 8601. An offset is mandatory: a naive
/// local time would silently mean a different instant on another device.
DateTime requiredTime(Object? value) {
  final parsed = value is String && _timeZone.hasMatch(value)
      ? DateTime.tryParse(value)
      : null;
  if (parsed == null) {
    throw const FormatException('Invalid message time');
  }
  return parsed;
}

DateTime? optionalTime(Object? value) {
  if (value == null) return null;
  return requiredTime(value);
}

final RegExp _timeZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');
