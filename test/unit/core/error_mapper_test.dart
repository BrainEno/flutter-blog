import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

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

    test('timeouts become timeout errors', () {
      final exception = mapToServerException(
        TimeoutException('request timed out after 30s'),
      );
      expect(exception.kind, FailureKind.timeout);
      expect(exception.toFailure().message, contains('超时'));
    });

    test('PostgREST 42501 becomes a permission error without SQL detail', () {
      final raw = sb.PostgrestException(
        message: 'permission denied for table blogs (details: policy xyz)',
        code: '42501',
      );
      final exception = mapToServerException(raw);
      final failure = exception.toFailure();
      expect(failure.kind, FailureKind.permission);
      expect(failure.message, '没有权限执行此操作');
      expect(failure.message, isNot(contains('permission denied')));
      expect(failure.message, isNot(contains('policy')));
      expect(failure.cause, same(raw));
    });

    test('PostgREST unique violation becomes a validation error', () {
      final exception = mapToServerException(
        sb.PostgrestException(message: 'duplicate key', code: '23505'),
      );
      expect(exception.kind, FailureKind.validation);
    });

    test('other PostgREST errors become generic server errors, no leakage', () {
      final exception = mapToServerException(
        sb.PostgrestException(message: 'syntax error at or near "SELECT"'),
      );
      final failure = exception.toFailure();
      expect(failure.kind, FailureKind.server);
      expect(failure.message, isNot(contains('SELECT')));
      expect(failure.message, isNot(contains('syntax')));
    });

    test('storage exceptions keep their category', () {
      final exception = mapToServerException(
        sb.StorageException('bucket not found', statusCode: '404'),
      );
      expect(exception.kind, FailureKind.storage);
    });

    test('auth exceptions keep their message (it is user-facing)', () {
      final exception = mapToServerException(
        sb.AuthException('New password should be at least 6 characters.'),
      );
      expect(exception.kind, FailureKind.auth);
      expect(exception.message, contains('6 characters'));
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
