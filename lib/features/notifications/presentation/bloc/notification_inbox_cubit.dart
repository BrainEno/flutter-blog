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

/// The first page itself could not be loaded (offline, unavailable deployment, ...).
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

  /// True while a silent first-page refresh is replacing the current page walk.
  final bool isRefreshing;

  /// True while the next older page is being fetched.
  final bool isLoadingMore;

  /// Whether another cursor request may be attempted. The API has no
  /// `hasMore` flag, so this remains true after any non-empty page until an
  /// empty response, a refresh, or a cursor-compatibility failure.
  final bool hasMore;

  /// A retryable failure loading an older page; already loaded rows stay visible.
  final Failure? loadMoreFailure;

  /// The server ignored or rejected the cursor, so retrying it would not advance.
  final bool paginationUnavailable;

  const NotificationInboxLoaded({
    required this.items,
    this.markingId,
    this.markingAll = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.loadMoreFailure,
    this.paginationUnavailable = false,
  });

  bool get isEmpty => items.isEmpty;

  /// The summary covers pages currently loaded in this view, not the full inbox.
  int get unreadCount => items.where((item) => !item.isRead).length;

  NotificationInboxLoaded copyWith({
    List<AppNotification>? items,
    String? markingId,
    bool clearMarkingId = false,
    bool? markingAll,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasMore,
    Failure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
    bool? paginationUnavailable,
  }) {
    return NotificationInboxLoaded(
      items: items ?? this.items,
      markingId: clearMarkingId ? null : (markingId ?? this.markingId),
      markingAll: markingAll ?? this.markingAll,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      loadMoreFailure: clearLoadMoreFailure
          ? null
          : (loadMoreFailure ?? this.loadMoreFailure),
      paginationUnavailable:
          paginationUnavailable ?? this.paginationUnavailable,
    );
  }
}

/// Reads and updates the signed-in account's notification inbox.
///
/// Reading happens when the screen opens and when the user asks for it: the
/// server has no push channel and this app does not poll. Older pages use the
/// server's `(createdAt, id)` cursor. Every request carries the fence that was
/// current when it started, and a result is dropped if the session or first-page
/// generation changed while it was in flight, so one account's inbox can never
/// be appended to another account's view.
class NotificationInboxCubit extends Cubit<NotificationInboxState> {
  NotificationInboxCubit({required this.repository, required this.identity})
    : super(const NotificationInboxLoading()) {
    _identitySubscription = identity.identityChanges.listen((_) {
      unawaited(load());
    });
    unawaited(load());
  }

  /// Number of rows requested per page; the server accepts up to 100.
  static const int pageLimit = 50;

  final NotificationRepository repository;
  final NowaveSessionIdentity identity;

  StreamSubscription<void>? _identitySubscription;
  String? _nextCursor;
  int _pageGeneration = 0;

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

  /// Reloads the newest page and resets any older pages already appended.
  /// [showLoading] is false for pull-to-refresh, which keeps the current rows on
  /// screen while the first page is fetched again.
  Future<void> load({bool showLoading = true}) async {
    if (!showLoading) {
      final current = state;
      if (current is NotificationInboxLoaded && current.markingAll) return;
    }
    final generation = ++_pageGeneration;
    _nextCursor = null;
    final fence = _fence;
    if (fence == null) {
      if (!isClosed) emit(const NotificationInboxSignedOut());
      return;
    }
    if (showLoading && !isClosed) {
      emit(const NotificationInboxLoading());
    } else {
      final current = state;
      if (!isClosed && current is NotificationInboxLoaded) {
        emit(
          current.copyWith(
            isRefreshing: true,
            isLoadingMore: false,
            hasMore: false,
            clearLoadMoreFailure: true,
            paginationUnavailable: false,
          ),
        );
      }
    }
    final result = await repository.list(fence: fence, limit: pageLimit);
    if (isClosed || !_stillCurrent(fence) || generation != _pageGeneration) {
      return;
    }
    result.fold((failure) => emit(NotificationInboxFailure(failure)), (page) {
      _nextCursor = page.nextCursor;
      emit(
        NotificationInboxLoaded(
          items: page.items,
          hasMore: page.nextCursor != null,
          paginationUnavailable:
              page.items.isNotEmpty && page.nextCursor == null,
        ),
      );
    });
  }

  /// Loads the next older page. Empty arrays are the API's end-of-inbox signal.
  /// Failures keep the rows and cursor so the same request can be retried.
  Future<void> loadMore() async {
    final fence = _fence;
    if (fence == null) {
      _nextCursor = null;
      _pageGeneration++;
      if (!isClosed) emit(const NotificationInboxSignedOut());
      return;
    }
    final current = state;
    final cursor = _nextCursor;
    if (current is! NotificationInboxLoaded ||
        cursor == null ||
        !current.hasMore ||
        current.isRefreshing ||
        current.isLoadingMore ||
        current.markingAll ||
        current.paginationUnavailable) {
      return;
    }

    final generation = _pageGeneration;
    emit(current.copyWith(isLoadingMore: true, clearLoadMoreFailure: true));
    final result = await repository.list(
      fence: fence,
      limit: pageLimit,
      cursor: cursor,
    );
    if (isClosed || !_stillCurrent(fence) || generation != _pageGeneration) {
      return;
    }
    final latest = state;
    if (latest is! NotificationInboxLoaded) return;

    result.fold(
      (failure) {
        if (failure.code == notificationCursorUnavailableFailureCode) {
          _nextCursor = null;
          emit(
            latest.copyWith(
              isLoadingMore: false,
              hasMore: false,
              clearLoadMoreFailure: true,
              paginationUnavailable: true,
            ),
          );
          return;
        }
        emit(latest.copyWith(isLoadingMore: false, loadMoreFailure: failure));
      },
      (page) {
        if (page.items.isEmpty) {
          _nextCursor = null;
          emit(
            latest.copyWith(
              isLoadingMore: false,
              hasMore: false,
              clearLoadMoreFailure: true,
            ),
          );
          return;
        }

        // Older deployments may ignore an unknown `cursor` query parameter and
        // answer the first page again. Never append repeats or offer an endless
        // retry loop; retain the current rows and explain the compatibility cap.
        if (page.nextCursor == null ||
            page.nextCursor == cursor ||
            _containsRepeatedId(latest.items, page.items)) {
          _nextCursor = null;
          emit(
            latest.copyWith(
              isLoadingMore: false,
              hasMore: false,
              clearLoadMoreFailure: true,
              paginationUnavailable: true,
            ),
          );
          return;
        }

        _nextCursor = page.nextCursor;
        emit(
          latest.copyWith(
            items: List<AppNotification>.unmodifiable([
              ...latest.items,
              ...page.items,
            ]),
            isLoadingMore: false,
            hasMore: true,
            clearLoadMoreFailure: true,
          ),
        );
      },
    );
  }

  static bool _containsRepeatedId(
    List<AppNotification> current,
    List<AppNotification> next,
  ) {
    final seen = current.map((item) => item.id).toSet();
    for (final item in next) {
      if (!seen.add(item.id)) return true;
    }
    return false;
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
    if (current is! NotificationInboxLoaded ||
        current.unreadCount == 0 ||
        current.markingAll ||
        current.isLoadingMore ||
        current.isRefreshing) {
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
