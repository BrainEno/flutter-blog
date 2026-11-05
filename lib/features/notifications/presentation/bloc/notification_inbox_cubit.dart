import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class NotificationInboxState {
  const NotificationInboxState();
}

final class NotificationInboxLoading extends NotificationInboxState {
  const NotificationInboxLoading();
}

/// Nobody is signed in, so there is no inbox to show.
final class NotificationInboxSignedOut extends NotificationInboxState {
  const NotificationInboxSignedOut();
}

/// The list itself could not be loaded (offline, unavailable deployment, ...).
final class NotificationInboxFailure extends NotificationInboxState {
  final Failure failure;

  const NotificationInboxFailure(this.failure);

  /// Display-safe fallback; the UI localizes via `localizedFailure`.
  String get error => failure.message;
}

final class NotificationInboxLoaded extends NotificationInboxState {
  final List<AppNotification> items;

  /// The row whose "mark as read" is in flight, if any.
  final String? markingId;

  /// True while "mark all as read" is in flight.
  final bool markingAll;

  const NotificationInboxLoaded({
    required this.items,
    this.markingId,
    this.markingAll = false,
  });

  bool get isEmpty => items.isEmpty;

  int get unreadCount => items.where((item) => !item.isRead).length;

  NotificationInboxLoaded copyWith({
    List<AppNotification>? items,
    String? markingId,
    bool clearMarkingId = false,
    bool? markingAll,
  }) {
    return NotificationInboxLoaded(
      items: items ?? this.items,
      markingId: clearMarkingId ? null : (markingId ?? this.markingId),
      markingAll: markingAll ?? this.markingAll,
    );
  }
}

/// Reads and updates the signed-in account's notification inbox.
///
/// Reading happens when the screen opens and when the user asks for it: the
/// server has no push channel and this app does not poll. Every request carries
/// the fence that was current when it started, and a result is dropped if the
/// session changed while it was in flight, so a sign-in switch can never show
/// one account's inbox to another.
class NotificationInboxCubit extends Cubit<NotificationInboxState> {
  NotificationInboxCubit({required this.repository, required this.identity})
    : super(const NotificationInboxLoading()) {
    _identitySubscription = identity.identityChanges.listen((_) {
      unawaited(load());
    });
    unawaited(load());
  }

  /// How many rows the inbox asks for. The server caps a page at 100 and
  /// offers no cursor, so this is also the newest window the app can show.
  static const int pageLimit = 50;

  final NotificationRepository repository;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;

  /// The fence of the account this screen belongs to, or null when nobody is
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

  /// Loads the inbox. [showLoading] is false for a silent refresh, which keeps
  /// the current list on screen instead of replacing it with a spinner.
  Future<void> load({bool showLoading = true}) async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const NotificationInboxSignedOut());
      return;
    }
    if (showLoading && !isClosed) emit(const NotificationInboxLoading());
    final result = await repository.list(fence: fence, limit: pageLimit);
    if (isClosed || !_stillCurrent(fence)) return;
    result.fold(
      (failure) => emit(NotificationInboxFailure(failure)),
      (items) => emit(NotificationInboxLoaded(items: items)),
    );
  }

  /// Marks one notification read and returns the failure, or null on success.
  Future<Failure?> markRead(String id) async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const NotificationInboxSignedOut());
      return null;
    }
    final current = state;
    if (current is! NotificationInboxLoaded) return null;
    emit(current.copyWith(markingId: id));
    final result = await repository.markRead(id, fence: fence);
    if (isClosed || !_stillCurrent(fence)) return null;
    return result.fold<Failure?>(
      (failure) {
        _clearMarking();
        return failure;
      },
      (updated) {
        final latest = state;
        if (latest is NotificationInboxLoaded) {
          emit(
            latest.copyWith(
              items: _replace(latest.items, updated),
              clearMarkingId: true,
            ),
          );
        }
        return null;
      },
    );
  }

  /// Marks everything read and returns the failure, or null on success.
  Future<Failure?> markAllRead() async {
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const NotificationInboxSignedOut());
      return null;
    }
    final current = state;
    if (current is! NotificationInboxLoaded || current.unreadCount == 0) {
      return null;
    }
    emit(current.copyWith(markingAll: true));
    final result = await repository.markAllRead(fence: fence);
    if (isClosed || !_stillCurrent(fence)) return null;
    return result.fold<Failure?>(
      (failure) {
        _setMarkingAll(false);
        return failure;
      },
      (_) {
        final latest = state;
        if (latest is NotificationInboxLoaded) {
          final now = DateTime.now();
          emit(
            latest.copyWith(
              items: List.unmodifiable(
                latest.items.map((item) => item.markedRead(now)),
              ),
              markingAll: false,
            ),
          );
        }
        return null;
      },
    );
  }

  void _clearMarking() {
    final latest = state;
    if (latest is NotificationInboxLoaded) {
      emit(latest.copyWith(clearMarkingId: true));
    }
  }

  void _setMarkingAll(bool value) {
    final latest = state;
    if (latest is NotificationInboxLoaded) {
      emit(latest.copyWith(markingAll: value));
    }
  }

  /// Replaces one row, keeping the server's order.
  static List<AppNotification> _replace(
    List<AppNotification> items,
    AppNotification updated,
  ) {
    return List.unmodifiable([
      for (final item in items)
        if (item.id == updated.id) updated else item,
    ]);
  }

  @override
  Future<void> close() async {
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    return super.close();
  }
}
