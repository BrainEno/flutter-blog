import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The unread-message total shown beside the profile's Messages entry.
///
/// The API has no global message unread-count endpoint and its conversation
/// list has no cursor. This badge therefore sums `unreadCount` from only the
/// newest [MessageInboxCubit.pageLimit] conversations; it must not be
/// presented as the exact total across the whole mailbox.
///
/// The list is read when this cubit is created, when the account changes, and
/// when the caller explicitly refreshes it (for example, after closing the
/// inbox). It never polls. A failed read retains the last known count, while a
/// session fence and request generation prevent stale responses from leaking
/// across accounts or overwriting a newer refresh.
class MessageUnreadBadgeCubit extends Cubit<int> {
  MessageUnreadBadgeCubit({required this.repository, required this.identity})
    : super(0) {
    _identitySubscription = identity.identityChanges.listen((_) {
      // Do not let a newly signed-in account briefly see the old count.
      if (!isClosed) emit(0);
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  final MessageRepository repository;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;
  int _refreshGeneration = 0;

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

  bool _stillCurrent(NowaveSessionFence fence) =>
      identity.activeUserId == fence.userId &&
      identity.sessionGeneration == fence.generation;

  /// Re-reads the recent conversation window and sums its per-conversation
  /// unread message counts. A failure leaves the last known value untouched.
  Future<void> refresh() async {
    final requestGeneration = ++_refreshGeneration;
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(0);
      return;
    }

    final result = await repository.conversations(
      fence: fence,
      limit: MessageInboxCubit.pageLimit,
    );
    if (isClosed ||
        requestGeneration != _refreshGeneration ||
        !_stillCurrent(fence)) {
      return;
    }
    result.fold((_) {}, (conversations) {
      final unreadCount = conversations
          .take(MessageInboxCubit.pageLimit)
          .fold<int>(
            0,
            (total, conversation) =>
                total +
                (conversation.unreadCount < 0 ? 0 : conversation.unreadCount),
          );
      if (!isClosed) emit(unreadCount);
    });
  }

  @override
  Future<void> close() async {
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    return super.close();
  }
}
