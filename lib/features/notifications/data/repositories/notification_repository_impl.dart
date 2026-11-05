import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/notifications/data/datasources/notification_codec.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The no-wave notification inbox.
///
/// The fence is handed to the HTTP client on every call, so a 401 cannot be
/// replayed as a different account. Nothing is cached, persisted or logged.
class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this.client);

  final NowaveApiClient client;

  /// The server accepts 1..100 and defaults to 50.
  static const int _kMaxLimit = 100;

  @override
  Future<Either<Failure, List<AppNotification>>> list({
    required NowaveSessionFence fence,
    int limit = 50,
  }) async {
    var bounded = limit;
    if (bounded < 1) bounded = 1;
    if (bounded > _kMaxLimit) bounded = _kMaxLimit;
    try {
      final data = await client.getJson(
        '/me/notifications',
        query: {'limit': '$bounded'},
        sessionFence: fence,
        followRedirects: false,
      );
      return right(_parseList(data, bounded));
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  @override
  Future<Either<Failure, AppNotification>> markRead(
    String id, {
    required NowaveSessionFence fence,
  }) async {
    if (id.isEmpty) {
      return left(
        const Failure(
          '通知标识无效',
          kind: FailureKind.validation,
          code: 'client.parse',
        ),
      );
    }
    try {
      final data = await client.putJson(
        '/me/notifications/${Uri.encodeComponent(id)}/read',
        null,
        sessionFence: fence,
      );
      return right(notificationFromRow(data));
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  @override
  Future<Either<Failure, int>> markAllRead({
    required NowaveSessionFence fence,
  }) async {
    try {
      final data = await client.postJson(
        '/me/notifications/read-all',
        null,
        sessionFence: fence,
      );
      if (data is! int) {
        throw const FormatException('Invalid read-all response');
      }
      return right(data);
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  List<AppNotification> _parseList(dynamic data, int limit) {
    if (data is! List || data.length > limit) {
      throw const FormatException('Invalid notification list');
    }
    return List.unmodifiable(data.map(notificationFromRow));
  }

  /// Deployments that predate the inbox answer 404/405; that is an honest
  /// "unavailable", not a broken request.
  Failure _failureOf(Object error) {
    if (error is NowaveApiException) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const Failure(
          '此服务器暂不提供通知',
          kind: FailureKind.server,
          code: 'notifications.unavailable',
        );
      }
      if (error.statusCode == 401) {
        return const Failure(
          '登录已过期，请重新登录',
          kind: FailureKind.auth,
          code: 'server.UNAUTHENTICATED',
        );
      }
      if (error.statusCode == 429) {
        return const Failure(
          '操作过于频繁，请稍后再试',
          kind: FailureKind.server,
          code: 'server.RATE_LIMITED',
        );
      }
      // The shared client reports a malformed success envelope as HTTP_200.
      if (error.statusCode >= 200 && error.statusCode < 300) {
        return _parseFailure();
      }
    }
    if (error is FormatException) return _parseFailure();
    // The mapper classifies network, timeout, auth, server and parse failures.
    // Its diagnostic cause is dropped: this screen needs no raw data.
    return mapErrorToFailure(error).forPresentation();
  }

  Failure _parseFailure() => const Failure(
    '通知数据格式错误，请更新应用后重试',
    kind: FailureKind.validation,
    code: 'client.parse',
  );
}
