import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';

/// Single place where raw exceptions become typed, display-safe errors.
///
/// The messages here are the ONLY text that may reach a snackbar; the
/// original exception is preserved as `cause` for logs.

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
      case 'UNAUTHENTICATED':
        return ServerException(
          '登录已过期，请重新登录',
          kind: FailureKind.auth,
          cause: error,
        );
      case 'FORBIDDEN':
        return ServerException(
          '没有权限执行此操作',
          kind: FailureKind.permission,
          cause: error,
        );
      case 'NOT_FOUND':
        return ServerException(
          '相关数据不存在或已被删除',
          kind: FailureKind.validation,
          cause: error,
        );
      case 'CONFLICT':
        return ServerException(
          '该内容已存在，请勿重复操作',
          kind: FailureKind.validation,
          cause: error,
        );
      case 'BAD_USER_INPUT':
        return ServerException(
          '提交的内容不符合要求，请检查后重试',
          kind: FailureKind.validation,
          cause: error,
        );
      case 'RATE_LIMITED':
        return ServerException(
          '操作过于频繁，请稍后再试',
          kind: FailureKind.server,
          cause: error,
        );
      case 'SERVICE_UNAVAILABLE':
        return ServerException(
          '服务器暂时不可用，请稍后重试',
          kind: FailureKind.server,
          cause: error,
        );
      default:
        return ServerException(
          '服务器开小差了，请稍后重试',
          kind: FailureKind.server,
          cause: error,
        );
    }
  }

  if (error is SocketException || error is HttpException) {
    return ServerException(
      '网络连接不可用，请检查网络',
      kind: FailureKind.network,
      cause: error,
    );
  }

  if (error is TimeoutException) {
    return ServerException(
      '请求超时，请稍后重试',
      kind: FailureKind.timeout,
      cause: error,
    );
  }

  if (error is FormatException) {
    return ServerException(
      '数据格式错误，请更新应用后重试',
      kind: FailureKind.validation,
      cause: error,
    );
  }

  return ServerException(
    '发生未知错误，请稍后重试',
    kind: FailureKind.unknown,
    cause: error,
  );
}
