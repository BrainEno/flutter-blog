import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The number of unread notifications, for the profile menu badge.
///
/// The state is a plain count because that is all the badge shows. `0` means
/// "show nothing": nobody is signed in, the inbox is clear, or the check could
/// not be answered. The one thing the badge never does is invent a number - a
/// failed refresh keeps whatever it knew (`0` on a cold start).
///
/// It reads once when the profile opens, whenever the account changes, and when
/// the caller asks (returning from the inbox). It does not poll: no-wave has no
/// push channel, so a badge that refreshed on a timer would only spend requests
/// to stay stale for as long as the user watches it.
class NotificationBadgeCubit extends Cubit<int> {
  NotificationBadgeCubit({required this.repository, required this.identity})
    : super(0) {
    _identitySubscription = identity.identityChanges.listen((_) {
      // A different account must never inherit the previous account's count,
      // not even for the moment the request takes.
      if (!isClosed) emit(0);
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  final NotificationRepository repository;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;
  int _refreshGeneration = 0;

  /// The fence of the account this badge belongs to, or null when nobody is
  /// signed in.
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

  /// Reads the count again. Safe to call as often as the caller likes; a
  /// failure leaves the badge showing what it last knew. Only the latest
  /// started refresh may update it; a failed refresh also invalidates older
  /// in-flight responses.
  Future<void> refresh() async {
    final requestGeneration = ++_refreshGeneration;
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(0);
      return;
    }
    final result = await repository.unreadCount(fence: fence);
    // A superseded request or response for a previous session cannot overwrite
    // the latest accepted count.
    if (isClosed ||
        requestGeneration != _refreshGeneration ||
        !_stillCurrent(fence)) {
      return;
    }
    result.fold((_) {}, (count) {
      if (!isClosed) emit(count < 0 ? 0 : count);
    });
  }

  @override
  Future<void> close() async {
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    return super.close();
  }
}
