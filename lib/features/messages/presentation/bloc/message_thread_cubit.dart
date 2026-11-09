import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class MessageThreadState {
  const MessageThreadState();
}

final class MessageThreadLoading extends MessageThreadState {
  const MessageThreadLoading();
}

final class MessageThreadSignedOut extends MessageThreadState {
  const MessageThreadSignedOut();
}

/// The conversation is not there, or not this account's.
///
/// The server deliberately answers the same way for both, so the screen says
/// the same thing for both - and offers no retry, because retrying will not
/// make it exist.
final class MessageThreadMissing extends MessageThreadState {
  const MessageThreadMissing();
}

/// A read that broke and is worth retrying (offline, timeout, 5xx).
final class MessageThreadFailure extends MessageThreadState {
  const MessageThreadFailure(this.failure);

  final Failure failure;
}

final class MessageThreadLoaded extends MessageThreadState {
  const MessageThreadLoaded({
    required this.viewerId,
    required this.conversation,
    required this.messages,
    this.hasMore = false,
    this.olderCursor,
    this.participants = const {},
    this.loadingOlder = false,
    this.olderFailure,
    this.markingRead = false,
    this.markedRead = false,
    this.sending = false,
    this.sendFailure,
  });

  final String viewerId;
  final Conversation conversation;

  /// Oldest first, the order the server returns a page in.
  final List<ConversationMessage> messages;

  /// True when the newest page was full, so older messages exist.
  final bool hasMore;

  /// The id of the oldest message on screen; the cursor for the next page.
  final String? olderCursor;

  final Map<String, MessageParticipant> participants;

  final bool loadingOlder;

  /// Why the last "older" attempt failed, if it did. The loaded page stays.
  final Failure? olderFailure;

  final bool markingRead;

  /// The server agreed that everything up to now is read.
  final bool markedRead;

  final bool sending;
  final Failure? sendFailure;

  bool get isEmpty => messages.isEmpty;

  int get unreadCount => conversation.unreadCount;

  MessageThreadLoaded copyWith({
    Conversation? conversation,
    List<ConversationMessage>? messages,
    bool? hasMore,
    String? olderCursor,
    bool clearOlderCursor = false,
    Map<String, MessageParticipant>? participants,
    bool? loadingOlder,
    Failure? olderFailure,
    bool clearOlderFailure = false,
    bool? markingRead,
    bool? markedRead,
    bool? sending,
    Failure? sendFailure,
    bool clearSendFailure = false,
  }) {
    return MessageThreadLoaded(
      viewerId: viewerId,
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      olderCursor: clearOlderCursor ? null : (olderCursor ?? this.olderCursor),
      participants: participants ?? this.participants,
      loadingOlder: loadingOlder ?? this.loadingOlder,
      olderFailure: clearOlderFailure
          ? null
          : (olderFailure ?? this.olderFailure),
      markingRead: markingRead ?? this.markingRead,
      markedRead: markedRead ?? this.markedRead,
      sending: sending ?? this.sending,
      sendFailure: clearSendFailure ? null : (sendFailure ?? this.sendFailure),
    );
  }
}

/// One conversation: its newest page of messages, older pages on request, the
/// explicit "mark read" action, and sending.
///
/// Paging walks backwards: the server returns the newest page (oldest first)
/// and takes a `before` cursor for everything older, so "older" prepends.
class MessageThreadCubit extends Cubit<MessageThreadState> {
  MessageThreadCubit({
    required this.conversationId,
    required this.repository,
    required this.identity,
    required this.names,
  }) : super(const MessageThreadLoading());

  /// The server's default and ceiling for one page of messages.
  static const int pageLimit = 100;

  final String conversationId;
  final MessageRepository repository;
  final NowaveSessionIdentity identity;
  final MessageParticipantNames names;

  NowaveSessionFence? get _fence {
    final userId = identity.activeUserId;
    final token = identity.accessToken;
    if (userId == null || userId.isEmpty) return null;
    if (token == null || token.isEmpty) return null;
    return NowaveSessionFence(
      userId: userId,
      generation: identity.sessionGeneration,
    );
  }

  bool _participantUpdateInProgress = false;

  bool _stillCurrent(NowaveSessionFence fence) {
    return identity.activeUserId == fence.userId &&
        identity.sessionGeneration == fence.generation;
  }

  /// Reads the conversation header and its newest page of messages.
  Future<void> load() async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const MessageThreadSignedOut());
      return;
    }
    if (!isClosed) emit(const MessageThreadLoading());

    final header = await repository.conversation(conversationId, fence: fence);
    if (isClosed || !_stillCurrent(fence)) return;
    final conversation = header.fold<Conversation?>(_missingOrNull, (v) => v);
    if (conversation == null) return;

    final page = await repository.messages(
      conversationId,
      fence: fence,
      limit: pageLimit,
    );
    if (isClosed || !_stillCurrent(fence)) return;
    final rows = page.fold<List<ConversationMessage>?>((failure) {
      emit(_failureState(failure));
      return null;
    }, (v) => v);
    if (rows == null) return;

    emit(
      MessageThreadLoaded(
        viewerId: fence.userId,
        conversation: conversation,
        messages: rows,
        hasMore: rows.length >= pageLimit,
        olderCursor: rows.isEmpty ? null : rows.first.id,
      ),
    );
    await _resolveNames(fence);
  }

  /// Picks up a conversation that changed while the page was open (a new
  /// message arrived, or the count was reset elsewhere). Never shows a spinner:
  /// the page it refreshes is already on screen.
  Future<void> refresh() async {
    final fence = _fence;
    final current = state;
    if (fence == null || current is! MessageThreadLoaded) return;
    final header = await repository.conversation(conversationId, fence: fence);
    if (isClosed || !_stillCurrent(fence)) return;
    final conversation = header.fold<Conversation?>(_missingOrNull, (v) => v);
    if (conversation == null) return;
    final latest = state;
    if (latest is! MessageThreadLoaded) return;
    emit(latest.copyWith(conversation: conversation));
  }

  /// Adds or removes members after a creator-only, history-aware confirmation.
  /// The server remains authoritative about ownership and membership.
  Future<Failure?> updateParticipants({
    List<String> addUserIds = const [],
    List<String> removeUserIds = const [],
  }) async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const MessageThreadSignedOut());
      return const Failure(
        'Sign in before managing conversation participants.',
        kind: FailureKind.auth,
        code: 'auth.notSignedIn',
      );
    }
    final current = state;
    if (current is! MessageThreadLoaded || current.viewerId != fence.userId) {
      return const Failure(
        'The conversation is no longer available.',
        kind: FailureKind.validation,
        code: 'messages.missing',
      );
    }
    if (current.conversation.createdBy != fence.userId) {
      return const Failure(
        'Participant management is restricted to the conversation creator.',
        kind: FailureKind.permission,
        code: 'messages.participantsForbidden',
      );
    }
    if (_participantUpdateInProgress) {
      return const Failure(
        'Another participant update is already in progress.',
        kind: FailureKind.validation,
        code: 'messages.participantsInProgress',
      );
    }
    if (addUserIds.isEmpty && removeUserIds.isEmpty) return null;

    _participantUpdateInProgress = true;
    try {
      final result = await repository.updateParticipants(
        conversationId,
        fence: fence,
        addUserIds: addUserIds,
        removeUserIds: removeUserIds,
      );
      if (isClosed || !_stillCurrent(fence)) {
        return const Failure(
          'The session changed before the participant update could be confirmed.',
          kind: FailureKind.auth,
          code: 'auth.sessionChanged',
        );
      }
      final latest = state;
      if (latest is! MessageThreadLoaded || latest.viewerId != fence.userId) {
        return const Failure(
          'The conversation is no longer available.',
          kind: FailureKind.validation,
          code: 'messages.missing',
        );
      }

      return result.fold<Failure?>(
        (failure) => failure.forPresentation(),
        (conversation) {
          final activeIds = conversation.participantIds.toSet();
          if (conversation.id != conversationId ||
              conversation.createdBy != fence.userId ||
              !activeIds.contains(fence.userId) ||
              addUserIds.any((id) => !activeIds.contains(id)) ||
              removeUserIds.any((id) => activeIds.contains(id))) {
            return const Failure(
              'The server returned an inconsistent participant update.',
              kind: FailureKind.validation,
              code: 'client.parse',
            );
          }
          final activeOthers = conversation.others(fence.userId).toSet();
          emit(
            latest.copyWith(
              conversation: conversation,
              participants: {
                for (final entry in latest.participants.entries)
                  if (activeOthers.contains(entry.key)) entry.key: entry.value,
              },
            ),
          );
          unawaited(_resolveNames(fence));
          return null;
        },
      );
    } finally {
      _participantUpdateInProgress = false;
    }
  }

  /// Loads the page before the oldest message on screen.
  Future<void> loadOlder() async {
    final fence = _fence;
    final current = state;
    if (fence == null || current is! MessageThreadLoaded) return;
    if (!current.hasMore ||
        current.loadingOlder ||
        current.olderCursor == null) {
      return;
    }
    final cursor = current.olderCursor;
    emit(current.copyWith(loadingOlder: true, clearOlderFailure: true));

    final page = await repository.messages(
      conversationId,
      fence: fence,
      limit: pageLimit,
      before: cursor,
    );
    if (isClosed || !_stillCurrent(fence)) return;
    final latest = state;
    if (latest is! MessageThreadLoaded) return;
    page.fold(
      (failure) =>
          emit(latest.copyWith(loadingOlder: false, olderFailure: failure)),
      (rows) {
        // Prepending keeps the reading position: the messages already on
        // screen stay where they are and the older ones go above them.
        final merged = _dedupe([...rows, ...latest.messages]);
        emit(
          latest.copyWith(
            messages: merged,
            hasMore: rows.length >= pageLimit,
            olderCursor: rows.isEmpty ? cursor : rows.first.id,
            loadingOlder: false,
            clearOlderFailure: true,
          ),
        );
      },
    );
  }

  /// Marks the whole conversation read. Explicit, because the server has no
  /// cursor: it marks everything it has already received, including messages
  /// this device never loaded.
  Future<Failure?> markRead() async {
    final fence = _fence;
    final current = state;
    if (fence == null) {
      if (!isClosed) emit(const MessageThreadSignedOut());
      return null;
    }
    if (current is! MessageThreadLoaded ||
        current.markingRead ||
        current.unreadCount == 0) {
      return null;
    }
    emit(current.copyWith(markingRead: true));
    final result = await repository.markRead(conversationId, fence: fence);
    if (isClosed || !_stillCurrent(fence)) return null;
    final latest = state;
    if (latest is! MessageThreadLoaded) return null;
    return result.fold<Failure?>(
      (failure) {
        emit(latest.copyWith(markingRead: false));
        return failure;
      },
      (marked) {
        // Only an explicit `true` from the server clears the count; anything
        // else leaves it where it was.
        emit(
          latest.copyWith(
            markingRead: false,
            markedRead: marked,
            conversation: marked
                ? latest.conversation.copyWith(unreadCount: 0)
                : null,
          ),
        );
        return null;
      },
    );
  }

  /// Sends one message. Returns the failure, or null when the server stored it
  /// (or replayed an earlier identical write).
  Future<Failure?> send({
    required String body,
    required String idempotencyKey,
  }) async {
    final fence = _fence;
    final current = state;
    if (fence == null) {
      if (!isClosed) emit(const MessageThreadSignedOut());
      return null;
    }
    if (current is! MessageThreadLoaded || current.sending) return null;
    emit(current.copyWith(sending: true, clearSendFailure: true));

    final result = await repository.sendMessage(
      conversationId,
      fence: fence,
      body: body,
      idempotencyKey: idempotencyKey,
    );
    if (isClosed || !_stillCurrent(fence)) return null;
    final latest = state;
    if (latest is! MessageThreadLoaded) return null;
    return result.fold<Failure?>(
      (failure) {
        emit(latest.copyWith(sending: false, sendFailure: failure));
        return failure;
      },
      (message) {
        emit(
          latest.copyWith(
            messages: _dedupe([...latest.messages, message]),
            sending: false,
            clearSendFailure: true,
          ),
        );
        return null;
      },
    );
  }

  /// Emits the state a failed header read deserves, and returns null so the
  /// caller stops. A missing conversation is not a retryable failure.
  Conversation? _missingOrNull(Failure failure) {
    if (!isClosed) emit(_failureState(failure));
    return null;
  }

  MessageThreadState _failureState(Failure failure) {
    if (failure.code == 'messages.missing' ||
        failure.code == 'messages.forbidden') {
      return const MessageThreadMissing();
    }
    return MessageThreadFailure(failure);
  }

  Future<void> _resolveNames(NowaveSessionFence fence) async {
    final current = state;
    if (current is! MessageThreadLoaded) return;
    final resolved = await names.resolve(
      current.conversation.others(fence.userId),
      limit: MessageParticipantNames.defaultLookupBudget,
    );
    if (isClosed || !_stillCurrent(fence) || resolved.isEmpty) return;
    final latest = state;
    if (latest is! MessageThreadLoaded) return;
    final activeIds = latest.conversation.others(fence.userId).toSet();
    final stillActive = {
      for (final entry in resolved.entries)
        if (activeIds.contains(entry.key)) entry.key: entry.value,
    };
    if (stillActive.isEmpty) return;
    emit(latest.copyWith(participants: {...latest.participants, ...stillActive}));
  }

  /// Replaces a message with the same id instead of listing it twice: a
  /// replayed send returns the original row.
  static List<ConversationMessage> _dedupe(List<ConversationMessage> messages) {
    final byId = <String, ConversationMessage>{};
    final order = <String>[];
    for (final message in messages) {
      if (!byId.containsKey(message.id)) order.add(message.id);
      byId[message.id] = message;
    }
    return List.unmodifiable([for (final id in order) byId[id]!]);
  }
}
