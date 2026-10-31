import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:http/http.dart' as http;

/// Single place where raw exceptions become typed, display-safe errors.
///
/// The messages here are display-safe Chinese text and remain the
/// fallback shown when no localization is available; the presentation
/// layer localizes via the stable `code` threaded into [Failure.code]
/// (see core/l10n/failure_l10n.dart). The original exception is
/// preserved as `cause` for logs.

/// Maps any thrown object to a [Failure]. [ServerException]s pass through
/// with their contract intact.
Failure mapErrorToFailure(Object error) {
  if (error is ServerException) return error.toFailure();
  return mapToServerException(error).toFailure();
}

/// Maps any thrown object to a display-safe [ServerException] for data
/// sources that throw towards their repository.
ServerException mapToServerException(Object error) {
  if (error is ServerException) return error;

  if (error is NowaveApiException) {
    // The backend's error codes are stable; its messages are English and
    // may embed validation details, so they are classified, never shown.
    switch (error.code) {
      case 'SESSION_CHANGED':
        return ServerException(
          '登录账户已变更；操作可能已提交，请先确认',
          kind: FailureKind.auth,
          code: 'auth.sessionChanged',
          cause: error,
        );
      case 'UNAUTHENTICATED':
        return ServerException(
          '登录已过期，请重新登录',
          kind: FailureKind.auth,
          code: 'server.UNAUTHENTICATED',
          cause: error,
        );
      case 'FORBIDDEN':
        return ServerException(
          '没有权限执行此操作',
          kind: FailureKind.permission,
          code: 'server.FORBIDDEN',
          cause: error,
        );
      case 'NOT_FOUND':
        return ServerException(
          '相关数据不存在或已被删除',
          kind: FailureKind.validation,
          code: 'server.NOT_FOUND',
          cause: error,
        );
      case 'CONFLICT':
        return ServerException(
          '该内容已存在，请勿重复操作',
          kind: FailureKind.validation,
          code: 'server.CONFLICT',
          cause: error,
        );
      case 'IDEMPOTENCY_CONFLICT':
        // Same Idempotency-Key reused with a different request (issue #19:
        // the server replays the original work on a same-key retry).
        return ServerException(
          '重复提交的内容不一致，请刷新后重试',
          kind: FailureKind.validation,
          code: 'server.IDEMPOTENCY_CONFLICT',
          cause: error,
        );
      case 'BAD_USER_INPUT':
        return ServerException(
          '提交的内容不符合要求，请检查后重试',
          kind: FailureKind.validation,
          code: 'server.BAD_USER_INPUT',
          cause: error,
        );
      case 'RATE_LIMITED':
        return ServerException(
          '操作过于频繁，请稍后再试',
          kind: FailureKind.server,
          code: 'server.RATE_LIMITED',
          cause: error,
        );
      case 'SERVICE_UNAVAILABLE':
        return ServerException(
          '服务器暂时不可用，请稍后重试',
          kind: FailureKind.server,
          code: 'server.SERVICE_UNAVAILABLE',
          cause: error,
        );
      default:
        return ServerException(
          '服务器开小差了，请稍后重试',
          kind: FailureKind.server,
          code: 'server.error',
          cause: error,
        );
    }
  }

  if (error is SocketException ||
      error is HttpException ||
      error is http.ClientException) {
    return ServerException(
      '网络连接不可用，请检查网络',
      kind: FailureKind.network,
      code: 'network.unavailable',
      cause: error,
    );
  }

  if (error is TimeoutException) {
    return ServerException(
      '请求超时，请稍后重试',
      kind: FailureKind.timeout,
      code: 'network.timeout',
      cause: error,
    );
  }

  if (error is FormatException) {
    return ServerException(
      '数据格式错误，请更新应用后重试',
      kind: FailureKind.validation,
      code: 'client.parse',
      cause: error,
    );
  }

  return ServerException(
    '发生未知错误，请稍后重试',
    kind: FailureKind.unknown,
    code: 'unknown',
    cause: error,
  );
}
