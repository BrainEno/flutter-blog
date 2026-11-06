import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';

sealed class MessageInboxState {
  const MessageInboxState();
}

final class MessageInboxLoading extends MessageInboxState {
  const MessageInboxLoading();
}

/// Nobody is signed in, so there is no inbox to show.
final class MessageInboxSignedOut extends MessageInboxState {
  const MessageInboxSignedOut();
}

/// The list itself could not be loaded (offline, unavailable deployment, ...).
final class MessageInboxFailure extends MessageInboxState {
  const MessageInboxFailure(this.failure);

  final Failure failure;
}

final class MessageInboxLoaded extends MessageInboxState {
  const MessageInboxLoaded({
    required this.viewerId,
    required this.conversations,
    this.participants = const {},
    this.startingRecipient,
  });

  /// The account these rows belong to, captured when they were read.
  final String viewerId;

  final List<Conversation> conversations;

  /// Identities resolved so far, by user id. Missing ids simply have no name
  /// yet; the UI says so instead of printing an id as a name.
  final Map<String, MessageParticipant> participants;

  /// The recipient of an in-flight "start a conversation", if any.
  final String? startingRecipient;

  bool get isEmpty => conversations.isEmpty;

  /// True when the server returned a full page, so older conversations exist
  /// but are not reachable (the endpoint has no cursor).
  bool get isCapped => conversations.length >= MessageInboxCubit.pageLimit;

  /// The conversation that already exists with exactly [recipientId] as its
  /// only other member, if there is one. This is what keeps "message this
  /// author" from opening a second thread with the same person.
  Conversation? existingWith(String recipientId) {
    for (final conversation in conversations) {
      final others = conversation.others(viewerId);
      if (others.length == 1 && others.single == recipientId) {
        return conversation;
      }
    }
    return null;
  }

  MessageInboxLoaded copyWith({
    List<Conversation>? conversations,
    Map<String, MessageParticipant>? participants,
    String? startingRecipient,
    bool clearStartingRecipient = false,
  }) {
    return MessageInboxLoaded(
      viewerId: viewerId,
      conversations: conversations ?? this.conversations,
      participants: participants ?? this.participants,
      startingRecipient: clearStartingRecipient
          ? null
          : (startingRecipient ?? this.startingRecipient),
    );
  }
}

/// The signed-in account's conversation list.
///
/// Read when the page opens, on pull-to-refresh, and when the account changes.
/// There is no polling and no push channel: the list states what the server
/// said at the moment it was read, and says so.
class MessageInboxCubit extends Cubit<MessageInboxState> {
  MessageInboxCubit({
    required this.repository,
    required this.identity,
    required this.names,
  }) : super(const MessageInboxLoading()) {
    _identitySubscription = identity.identityChanges.listen((_) {
      unawaited(load());
    });
    unawaited(load());
  }

  /// The server caps a page at 100 and offers no cursor; the app asks for 50.
  static const int pageLimit = 50;

  final MessageRepository repository;
  final NowaveSessionIdentity identity;
  final MessageParticipantNames names;

  StreamSubscription<void>? _identitySubscription;

  /// The recipient and key of a conversation this page is trying to open.
  /// Changing the recipient mints a new key; retrying the same one reuses it.
  String? _pendingRecipient;
  String? _pendingKey;

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

  bool _stillCurrent(NowaveSessionFence fence) {
    return identity.activeUserId == fence.userId &&
        identity.sessionGeneration == fence.generation;
  }

  /// Loads the conversation list. [showLoading] is false for a silent refresh,
  /// which keeps the current rows on screen.
  Future<void> load({bool showLoading = true}) async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const MessageInboxSignedOut());
      return;
    }
    if (showLoading && !isClosed) emit(const MessageInboxLoading());
    final result = await repository.conversations(
      fence: fence,
      limit: pageLimit,
    );
    if (isClosed || !_stillCurrent(fence)) return;
    final state = result.fold<MessageInboxState>(
      MessageInboxFailure.new,
      (rows) => MessageInboxLoaded(
        viewerId: fence.userId,
        conversations: rows,
      ),
    );
    emit(state);
    if (state is! MessageInboxLoaded) return;

    // Names arrive afterwards: the list is usable without them, and waiting
    // for a dozen public profiles before showing anything would be wrong.
    final resolved = await names.resolve(
      [for (final row in state.conversations) ...row.others(fence.userId)],
      limit: MessageInboxCubit.nameLookupBudget,
    );
    if (isClosed || !_stillCurrent(fence)) return;
    final latest = this.state;
    if (latest is! MessageInboxLoaded) return;
    if (resolved.isEmpty) return;
    emit(latest.copyWith(participants: {...latest.participants, ...resolved}));
  }

  /// How many participant identities one load may resolve.
  static const int nameLookupBudget =
      MessageParticipantNames.defaultLookupBudget;

  /// The public identity behind [userId], for a conversation that does not
  /// exist yet (the "发私信" entry from an author page). Null when the server
  /// has no profile for it or the lookup failed; the caller then says it does
  /// not know who this is rather than showing an id as a name.
  Future<MessageParticipant?> resolveParticipant(String userId) =>
      names.lookup(userId);

  /// Opens (or reuses) a conversation with [recipientId].
  ///
  /// Returns the conversation id, or the failure that stopped it. The same
  /// intent keeps its idempotency key across retries, so a lost response does
  /// not become a second conversation with the same person.
  Future<Either<Failure, String>> startConversation(String recipientId) async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const MessageInboxSignedOut());
      return left(
        const Failure(
          '登录后才能发私信',
          kind: FailureKind.auth,
          code: 'server.UNAUTHENTICATED',
        ),
      );
    }
    if (recipientId == fence.userId) {
      return left(
        const Failure(
          '不能给自己发私信',
          kind: FailureKind.validation,
          code: 'messages.invalid',
        ),
      );
    }
    final current = state;
    if (current is MessageInboxLoaded) {
      final existing = current.existingWith(recipientId);
      if (existing != null) return right(existing.id);
      if (current.startingRecipient != null) {
        return left(
          const Failure(
            '正在创建上一个会话，请稍候',
            kind: FailureKind.validation,
            code: 'messages.starting',
          ),
        );
      }
      emit(current.copyWith(startingRecipient: recipientId));
    }

    if (_pendingRecipient != recipientId || _pendingKey == null) {
      _pendingRecipient = recipientId;
      _pendingKey = const Uuid().v4();
    }
    final result = await repository.startConversation(
      fence: fence,
      recipientId: recipientId,
      idempotencyKey: _pendingKey!,
    );
    if (isClosed || !_stillCurrent(fence)) {
      return left(
        const Failure(
          '登录状态已变化，请重试',
          kind: FailureKind.auth,
          code: 'auth.sessionChanged',
        ),
      );
    }
    return result.fold(
      (failure) {
        _clearStarting();
        // A conflicting key means the key, not the request, is the problem:
        // the next attempt must mint a fresh one.
        if (failure.code == 'server.IDEMPOTENCY_CONFLICT') {
          _pendingRecipient = null;
          _pendingKey = null;
        }
        return left(failure);
      },
      (conversation) {
        _pendingRecipient = null;
        _pendingKey = null;
        _clearStarting();
        unawaited(load(showLoading: false));
        return right(conversation.id);
      },
    );
  }

  void _clearStarting() {
    final latest = state;
    if (latest is MessageInboxLoaded) {
      emit(latest.copyWith(clearStartingRecipient: true));
    }
  }

  @override
  Future<void> close() async {
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    return super.close();
  }
}
