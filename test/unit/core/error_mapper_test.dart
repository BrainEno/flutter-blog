import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('mapToServerException classifies by exception type', () {
    test('socket failures become network errors', () {
      final exception = mapToServerException(
        const SocketException('os error: network is unreachable'),
      );
      expect(exception.kind, FailureKind.network);
      expect(exception.toFailure().kind, FailureKind.network);
      expect(exception.message, contains('网络'));
    });

    test('HTTP transport failures become safe network errors', () {
      final raw = http.ClientException('private connection detail');
      final exception = mapToServerException(raw);
      expect(exception.kind, FailureKind.network);
      expect(exception.code, 'network.unavailable');
      expect(exception.message, isNot(contains('private connection detail')));
      expect(exception.cause, same(raw));
    });

    test('timeouts become timeout errors', () {
      final exception = mapToServerException(
        TimeoutException('request timed out after 30s'),
      );
      expect(exception.kind, FailureKind.timeout);
      expect(exception.toFailure().message, contains('超时'));
    });

    test('NowaveApiException FORBIDDEN becomes a permission error without '
        'backend detail', () {
      final raw = const NowaveApiException(
        statusCode: 403,
        code: 'FORBIDDEN',
        message: 'actor does not own article 123',
      );
      final exception = mapToServerException(raw);
      final failure = exception.toFailure();
      expect(failure.kind, FailureKind.permission);
      expect(failure.message, '没有权限执行此操作');
      expect(failure.message, isNot(contains('actor')));
      expect(failure.message, isNot(contains('article')));
      expect(failure.cause, same(raw));
    });

    test('NowaveApiException CONFLICT becomes a validation error', () {
      final exception = mapToServerException(
        const NowaveApiException(
          statusCode: 409,
          code: 'CONFLICT',
          message: 'identity already exists',
        ),
      );
      expect(exception.kind, FailureKind.validation);
    });

    test(
      'NowaveApiException IDEMPOTENCY_CONFLICT becomes a validation error',
      () {
        final exception = mapToServerException(
          NowaveApiException(
            statusCode: 409,
            code: 'IDEMPOTENCY_CONFLICT',
            message: 'idempotency key reused with a different request',
          ),
        );
        expect(exception.kind, FailureKind.validation);
      },
    );

    test('NowaveApiException NOT_FOUND becomes a validation error', () {
      final exception = mapToServerException(
        const NowaveApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'The article was not found.',
        ),
      );
      expect(exception.kind, FailureKind.validation);
      expect(exception.message, contains('不存在'));
    });

    test('NowaveApiException UNAUTHENTICATED becomes an auth error', () {
      final exception = mapToServerException(
        const NowaveApiException(
          statusCode: 401,
          code: 'UNAUTHENTICATED',
          message: 'Authentication is required.',
        ),
      );
      expect(exception.kind, FailureKind.auth);
      expect(exception.message, contains('重新登录'));
    });

    test('NowaveApiException RATE_LIMITED becomes a server error with a '
        'friendly message', () {
      final raw = const NowaveApiException(
        statusCode: 429,
        code: 'RATE_LIMITED',
        message: 'too many requests',
        retryAfterSeconds: 42,
      );
      final exception = mapToServerException(raw);
      expect(exception.kind, FailureKind.server);
      expect(exception.message, contains('频繁'));
      expect(exception.cause, same(raw));
    });

    test('NowaveApiException BAD_USER_INPUT becomes a validation error '
        'without echoing backend text', () {
      final exception = mapToServerException(
        const NowaveApiException(
          statusCode: 400,
          code: 'BAD_USER_INPUT',
          message: 'title must be a string.',
        ),
      );
      final failure = exception.toFailure();
      expect(failure.kind, FailureKind.validation);
      expect(failure.message, isNot(contains('title')));
      expect(failure.message, isNot(contains('string')));
    });

    test('unknown NowaveApiException codes become generic server errors, '
        'no leakage', () {
      final exception = mapToServerException(
        const NowaveApiException(
          statusCode: 500,
          code: 'INTERNAL_SERVER_ERROR',
          message: 'The request could not be completed.',
        ),
      );
      final failure = exception.toFailure();
      expect(failure.kind, FailureKind.server);
      expect(failure.message, isNot(contains('completed')));
    });

    test('unknown errors get a safe generic message and keep the cause', () {
      final raw = StateError('token=secret user@example.com');
      final exception = mapToServerException(raw);
      final failure = exception.toFailure();
      expect(failure.kind, FailureKind.unknown);
      expect(failure.message, '发生未知错误，请稍后重试');
      expect(failure.message, isNot(contains('secret')));
      expect(failure.cause, same(raw));
    });

    test('format exceptions become validation errors', () {
      final exception = mapToServerException(const FormatException('bad'));
      expect(exception.kind, FailureKind.validation);
    });

    test('ServerException instances pass through untouched', () {
      const original = ServerException('server unavailable');
      expect(mapToServerException(original), same(original));
      expect(mapErrorToFailure(original).message, 'server unavailable');
    });
  });

  group('Failure factories', () {
    test('each factory tags the right kind and a stable code', () {
      expect(Failure.networkOffline().kind, FailureKind.network);
      expect(Failure.networkOffline().code, 'network.offline');
      expect(Failure.timeout().kind, FailureKind.timeout);
      expect(Failure.permission().kind, FailureKind.permission);
      expect(Failure.storage().kind, FailureKind.storage);
      expect(Failure.server('x').kind, FailureKind.server);
      expect(Failure.unknown().kind, FailureKind.unknown);
    });

    test('toString mentions kind, code and diagnostics context', () {
      final failure = Failure.unknown(cause: StateError('boom'));
      expect(failure.toString(), contains('unknown'));
      // The cause rides along for development inspection only; the UI
      // renders [Failure.message], never toString().
      expect(failure.toString(), contains('boom'));
    });
  });
}
