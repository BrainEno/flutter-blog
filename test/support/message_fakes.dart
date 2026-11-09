import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:fpdart/fpdart.dart';

/// A session the message screens can fence against, switchable from tests.
class MessageTestIdentity implements NowaveSessionIdentity {
  String? userId = 'user-a';
  String? token = 'fake-token-a';
  int generation = 1;
  final StreamController<void> controller = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  String? get activeUserId => userId;

  @override
  String? get accessToken => token;

  @override
  int get sessionGeneration => generation;

  @override
  Stream<void> get identityChanges => controller.stream;

  void replace(String? user) {
    generation++;
    userId = user;
    token = user == null ? null : 'fake-replacement-token';
    controller.add(null);
  }

  Future<void> close() => controller.close();
}

Conversation testConversation({
  String id = 'conversation-1',
  List<String> participants = const ['user-a', 'user-b'],
  int unreadCount = 0,
  ConversationMessage? lastMessage,
  DateTime? lastActivityAt,
}) => Conversation(
  id: id,
  participantIds: participants,
  unreadCount: unreadCount,
  createdBy: participants.isEmpty ? null : participants.first,
  createdAt: DateTime.utc(2026, 11, 5, 4),
  lastActivityAt: lastActivityAt ?? DateTime.utc(2026, 11, 5, 4, 30),
  lastMessage:
      lastMessage ??
      testMessage(
        id: '$id-last',
        conversationId: id,
        senderId: participants.length > 1 ? participants[1] : 'user-b',
        body: '你好',
      ),
);

/// A message the viewer just stored: a fresh id, so a test can tell it apart
/// from the page it already had.
ConversationMessage _sentMessage(int count, String body) =>
    testMessage(id: 'sent-$count', body: body, senderId: 'user-a');

ConversationMessage testMessage({
  String id = 'message-1',
  String conversationId = 'conversation-1',
  String senderId = 'user-b',
  String body = '你好',
  DateTime? createdAt,
  bool duplicate = false,
}) => ConversationMessage(
  id: id,
  conversationId: conversationId,
  senderId: senderId,
  body: body,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 5, 4, 30),
  duplicate: duplicate,
);

const Failure testOffline = Failure(
  '无法连接到网络，请检查网络设置',
  kind: FailureKind.network,
  code: 'network.unavailable',
);

/// A conversation API whose every answer a test can arrange.
class FakeMessageRepository implements MessageRepository {
  List<Conversation> conversationsResult = const [];
  Conversation? conversationResult;
  List<ConversationMessage> messagesResult = const [];

  Failure? conversationsFailure;
  Failure? conversationFailure;
  Failure? messagesFailure;
  Failure? markReadFailure;
  Failure? deleteConversationFailure;
  Failure? startFailure;
  Failure? sendFailure;

  bool markReadResult = true;
  bool deleteConversationResult = true;
  Conversation? startResult;
  ConversationMessage? sendResult;

  /// Failures the page has to tell apart from "missing".
  Failure? missingConversationFailure = const Failure(
    '会话不存在，或你不属于这个会话',
    kind: FailureKind.validation,
    code: 'messages.missing',
  );

  final List<String> calls = [];
  final List<NowaveSessionFence> fences = [];
  final List<String> deletedConversationIds = [];
  final List<({String recipient, String key})> startRequests = [];
  final List<({String body, String key})> sendRequests = [];
  final List<String?> beforeCursors = [];

  /// When set, `conversations()` waits for it before answering, so a test can
  /// switch accounts while the request is in flight.
  Completer<void>? conversationsGate;
  Completer<void>? deleteConversationGate;

  @override
  Future<Either<Failure, List<Conversation>>> conversations({
    required NowaveSessionFence fence,
    int limit = 50,
  }) async {
    calls.add('conversations');
    fences.add(fence);
    final gate = conversationsGate;
    if (gate != null) await gate.future;
    final failure = conversationsFailure;
    if (failure != null) return left(failure);
    return right(conversationsResult);
  }

  @override
  Future<Either<Failure, Conversation>> conversation(
    String conversationId, {
    required NowaveSessionFence fence,
  }) async {
    calls.add('conversation:$conversationId');
    fences.add(fence);
    final failure = conversationFailure;
    if (failure != null) return left(failure);
    final conversation = conversationResult;
    if (conversation == null) {
      return left(
        missingConversationFailure ??
            const Failure('missing', kind: FailureKind.validation),
      );
    }
    return right(conversation);
  }

  @override
  Future<Either<Failure, List<ConversationMessage>>> messages(
    String conversationId, {
    required NowaveSessionFence fence,
    int limit = 100,
    String? before,
  }) async {
    calls.add('messages:$conversationId');
    fences.add(fence);
    beforeCursors.add(before);
    final failure = messagesFailure;
    if (failure != null) return left(failure);
    return right(messagesResult);
  }

  @override
  Future<Either<Failure, bool>> markRead(
    String conversationId, {
    required NowaveSessionFence fence,
  }) async {
    calls.add('markRead:$conversationId');
    fences.add(fence);
    final failure = markReadFailure;
    if (failure != null) return left(failure);
    return right(markReadResult);
  }

  @override
  Future<Either<Failure, bool>> deleteConversation(
    String conversationId, {
    required NowaveSessionFence fence,
  }) async {
    calls.add('delete:$conversationId');
    fences.add(fence);
    deletedConversationIds.add(conversationId);
    final gate = deleteConversationGate;
    if (gate != null) await gate.future;
    final failure = deleteConversationFailure;
    if (failure != null) return left(failure);
    return right(deleteConversationResult);
  }

  @override
  Future<Either<Failure, Conversation>> startConversation({
    required NowaveSessionFence fence,
    required String recipientId,
    required String idempotencyKey,
  }) async {
    calls.add('start:$recipientId');
    fences.add(fence);
    startRequests.add((recipient: recipientId, key: idempotencyKey));
    final failure = startFailure;
    if (failure != null) return left(failure);
    return right(startResult ?? testConversation());
  }

  @override
  Future<Either<Failure, ConversationMessage>> sendMessage(
    String conversationId, {
    required NowaveSessionFence fence,
    required String body,
    required String idempotencyKey,
  }) async {
    calls.add('send:$conversationId');
    fences.add(fence);
    sendRequests.add((body: body, key: idempotencyKey));
    final failure = sendFailure;
    if (failure != null) return left(failure);
    final message = sendResult ?? _sentMessage(sendRequests.length, body);
    return right(message);
  }
}

/// Participant names without any network: what a test puts in is what it gets.
class FakeParticipantNames implements MessageParticipantNames {
  FakeParticipantNames([Map<String, String>? names])
    : names = names ?? {'user-b': '读者乙', 'user-c': '读者丙'};

  final Map<String, String> names;

  /// Set to make every lookup fail, as an offline device would.
  bool failAll = false;

  final List<String> lookups = [];
  final List<int> budgets = [];

  @override
  Future<MessageParticipant?> lookup(String userId) async {
    lookups.add(userId);
    if (failAll) return null;
    final name = names[userId];
    if (name == null) return null;
    return MessageParticipant(userId: userId, displayName: name);
  }

  @override
  Future<Map<String, MessageParticipant>> resolve(
    Iterable<String> ids, {
    int limit = MessageParticipantNames.defaultLookupBudget,
  }) async {
    budgets.add(limit);
    final result = <String, MessageParticipant>{};
    for (final id in ids.toSet()) {
      final participant = await lookup(id);
      if (participant != null) result[id] = participant;
    }
    return result;
  }
}
