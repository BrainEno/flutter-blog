import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:fpdart/fpdart.dart';

/// The signed-in account's private conversations (`conversations*`).
///
/// Every call takes a [NowaveSessionFence]: a conversation belongs to one
/// account pair, and a response that arrives after a sign-in switch must not be
/// adopted by whoever replaced it. Nothing here is persisted.
abstract interface class MessageRepository {
  /// The member's conversations, newest activity first. The server caps a page
  /// at 100 and has no cursor, so this is the newest window only.
  Future<Either<Failure, List<Conversation>>> conversations({
    required NowaveSessionFence fence,
    int limit = 50,
  });

  /// One conversation's header: participants, unread count, last message.
  ///
  /// A conversation the caller is not a member of answers exactly like one that
  /// does not exist; membership is not something the server lets anyone probe.
  Future<Either<Failure, Conversation>> conversation(
    String conversationId, {
    required NowaveSessionFence fence,
  });

  /// One page of messages, oldest first. [before] is the id of the oldest
  /// message already on screen; older pages are addressed by it.
  Future<Either<Failure, List<ConversationMessage>>> messages(
    String conversationId, {
    required NowaveSessionFence fence,
    int limit = 100,
    String? before,
  });

  /// Marks the whole conversation read and returns whether the server agreed.
  ///
  /// The server has no cursor: it marks everything it has received by the time
  /// it handles the request, which may include messages this device never
  /// loaded. That is why the app makes this an explicit action.
  Future<Either<Failure, bool>> markRead(
    String conversationId, {
    required NowaveSessionFence fence,
  });

  /// Permanently deletes a conversation for every participant.
  ///
  /// Only its creator may do this. `false` means the conversation was already
  /// gone; callers must not treat it as a successful delete.
  Future<Either<Failure, bool>> deleteConversation(
    String conversationId, {
    required NowaveSessionFence fence,
  });

  /// Opens a conversation with [recipientId].
  ///
  /// Opening is not idempotent server-side - the same participants can be in
  /// two conversations - so the caller must pass a stable [idempotencyKey] and
  /// keep it while retrying the same intent, or a lost response becomes a
  /// second conversation.
  Future<Either<Failure, Conversation>> startConversation({
    required NowaveSessionFence fence,
    required String recipientId,
    required String idempotencyKey,
  });

  /// Sends one plain-text message.
  ///
  /// [idempotencyKey] is required by the server for the same reason: a retried
  /// send must replay the stored message, not post it twice. The returned row's
  /// `duplicate` flag says the server replayed an earlier write.
  Future<Either<Failure, ConversationMessage>> sendMessage(
    String conversationId, {
    required NowaveSessionFence fence,
    required String body,
    required String idempotencyKey,
  });
}
