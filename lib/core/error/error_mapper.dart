import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

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

  if (error is sb.AuthException) {
    // Supabase auth messages ("New password should be at least 6
    // characters.") are user-facing and worth showing verbatim; the raw
    // exception itself stays in `cause`.
    return ServerException(
      error.message.isNotEmpty ? error.message : '认证失败，请重新登录',
      kind: FailureKind.auth,
      cause: error,
    );
  }

  if (error is sb.PostgrestException) {
    // PostgREST messages can embed SQL and schema details - never surface
    // them. Classify by the PostgreSQL / PostgREST error code instead.
    switch (error.code) {
      case '42501':
        return ServerException(
          '没有权限执行此操作',
          kind: FailureKind.permission,
          cause: error,
        );
      case '23505':
        return ServerException(
          '该内容已存在，请勿重复操作',
          kind: FailureKind.validation,
          cause: error,
        );
      case '23503':
        return ServerException(
          '相关数据不存在或已被删除',
          kind: FailureKind.validation,
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

  if (error is sb.StorageException) {
    return ServerException(
      '文件存储服务暂时不可用，请稍后重试',
      kind: FailureKind.storage,
      cause: error,
    );
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
