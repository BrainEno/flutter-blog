import 'dart:convert';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/notifications/data/datasources/notification_codec.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/entities/notification_page.dart';
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
  static const int _kMaxCursorLength = 512;
  static final RegExp _cursorTimestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );
  static final RegExp _cursorId = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  Future<Either<Failure, NotificationPage>> list({
    required NowaveSessionFence fence,
    int limit = 50,
    String? cursor,
  }) async {
    var bounded = limit;
    if (bounded < 1) bounded = 1;
    if (bounded > _kMaxLimit) bounded = _kMaxLimit;
    final query = <String, String>{'limit': '$bounded'};
    if (cursor != null) query['cursor'] = cursor;
    try {
      final data = await client.getJson(
        '/me/notifications',
        query: query,
        sessionFence: fence,
        followRedirects: false,
      );
      return right(_parsePage(data, bounded));
    } catch (error) {
      return left(_failureOf(error, cursorRequest: cursor != null));
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
      final updated = notificationFromRow(data);
      if (updated.id != id || !updated.isRead) {
        throw const FormatException('Invalid mark-read response');
      }
      return right(updated);
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
      if (data is! int || data < 0) {
        throw const FormatException('Invalid read-all response');
      }
      return right(data);
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  @override
  Future<Either<Failure, int>> unreadCount({
    required NowaveSessionFence fence,
  }) async {
    try {
      final data = await client.getJson(
        '/me/notifications/unread-count',
        sessionFence: fence,
      );
      if (data is! int || data < 0) {
        throw const FormatException('Invalid unread count');
      }
      return right(data);
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  NotificationPage _parsePage(dynamic data, int limit) {
    if (data is! List || data.length > limit) {
      throw const FormatException('Invalid notification list');
    }
    final items = List<AppNotification>.unmodifiable(
      data.map(notificationFromRow),
    );
    if (data.isEmpty) return NotificationPage(items: items, nextCursor: null);

    // Preserve the timestamp exactly as it arrived. The backend compares this
    // millisecond ISO string against its indexed `(created_at, id)` key; parsing
    // and formatting it through DateTime would make the cursor depend on local
    // timezone or precision rules.
    final last = data.last;
    if (last is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification cursor row');
    }
    final createdAt = last['createdAt'];
    final id = last['id'];
    if (createdAt is! String ||
        !_cursorTimestamp.hasMatch(createdAt) ||
        DateTime.tryParse(createdAt) == null ||
        id is! String ||
        !_cursorId.hasMatch(id)) {
      throw const FormatException('Invalid notification cursor row');
    }
    final cursor = base64Url
        .encode(utf8.encode('$createdAt|$id'))
        .replaceAll('=', '');
    if (cursor.isEmpty || cursor.length > _kMaxCursorLength) {
      throw const FormatException('Invalid notification cursor');
    }
    return NotificationPage(items: items, nextCursor: cursor);
  }

  /// Deployments that predate the inbox answer 404/405; that is an honest
  /// "unavailable", not a broken request. A cursor-only 400 also means this
  /// server cannot continue the page contract; the cubit turns it into a
  /// localized compatibility notice while keeping the rows already loaded.
  Failure _failureOf(Object error, {bool cursorRequest = false}) {
    if (error is NowaveApiException) {
      if (cursorRequest && error.statusCode == 400) {
        return const Failure(
          'The server rejected notification pagination.',
          kind: FailureKind.server,
          code: notificationCursorUnavailableFailureCode,
        );
      }
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
