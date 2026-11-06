import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:fpdart/fpdart.dart';

/// The signed-in account's notification inbox (`me.notifications*`).
///
/// Every call takes a [NowaveSessionFence]: the inbox belongs to one account,
/// and a request that started before a sign-in change must not be adopted by
/// the account that replaced it. Nothing here is cached on disk.
abstract interface class NotificationRepository {
  /// Newest first. The server caps `limit` at 100 and defaults to 50.
  Future<Either<Failure, List<AppNotification>>> list({
    required NowaveSessionFence fence,
    int limit = 50,
  });

  /// Marks one notification read and returns the server's row.
  Future<Either<Failure, AppNotification>> markRead(
    String id, {
    required NowaveSessionFence fence,
  });

  /// Marks every unread notification read; returns how many changed.
  Future<Either<Failure, int>> markAllRead({required NowaveSessionFence fence});

  /// How many notifications this account has not read yet.
  ///
  /// Asked for by the profile menu badge, which needs one number and not a
  /// page of rows: the list only knows the unread count of the newest 50.
  Future<Either<Failure, int>> unreadCount({required NowaveSessionFence fence});
}
