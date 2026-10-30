import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/diagnostics_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// An error object whose text embeds everything that must never reach
/// the diagnostics buffer.
class _BoobyTrappedError implements Exception {
  @override
  String toString() =>
      'token=secret-token user=user@example.invalid password=hunter2';
}

void main() {
  setUp(AppLogger.clearDiagnostics);

  group('DiagnosticsBuffer', () {
    test('records the error message and type, never the error text', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordError(
        'refreshing the session failed; keeping the session',
        _BoobyTrappedError(),
      );

      final report = buffer.export();
      expect(report, contains('refreshing the session failed'));
      expect(report, contains('_BoobyTrappedError'));
      expect(report.contains('secret-token'), isFalse);
      expect(report.contains('user@example.invalid'), isFalse);
      expect(report.contains('hunter2'), isFalse);
    });

    test('a missing error object is still a useful record', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordError('persisting the session failed', null);

      expect(buffer.export(), contains('no error object'));
    });

    test('request records carry method, path, status and duration', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordRequest('POST', '/api/v1/articles', 503, 1203);

      final report = buffer.export();
      expect(report, contains('POST /api/v1/articles -> 503 (1203ms)'));
    });

    test('query strings and fragments never reach the buffer', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordRequest(
        'GET',
        '/api/v1/articles?token=secret-token',
        500,
        10,
      );
      buffer.recordError('failed#user@example.invalid', null);

      final report = buffer.export();
      expect(report, contains('GET /api/v1/articles -> 500'));
      expect(report, contains('failed'));
      expect(report.contains('secret-token'), isFalse);
      expect(report.contains('user@example.invalid'), isFalse);
    });

    test('transport failures record the method, path and error type', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordUnreachable('POST', '/api/v1/me/media', 'SocketException');

      expect(
        buffer.export(),
        contains('request POST /api/v1/me/media unreachable (SocketException)'),
      );
    });

    test('transport failures never keep the query string', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordUnreachable(
        'GET',
        '/api/v1/articles?token=secret-token',
        'ClientException',
      );

      expect(buffer.export(), contains('/api/v1/articles unreachable'));
      expect(buffer.export().contains('secret-token'), isFalse);
    });

    test('malformed responses record status and a fixed reason token', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordMalformed('GET', '/api/v1/articles', 502, 'non-json');

      expect(
        buffer.export(),
        contains('response GET /api/v1/articles -> 502 malformed (non-json)'),
      );
    });

    test('timeout records carry the budget', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordTimeout('GET', '/api/v1/articles', 10000);

      expect(
        buffer.export(),
        contains('timeout GET /api/v1/articles (budget 10000ms)'),
      );
    });

    test('the buffer is bounded and drops the oldest entries first', () {
      final buffer = DiagnosticsBuffer(capacity: 3);

      for (var i = 1; i <= 4; i++) {
        buffer.recordRequest('GET', '/api/v1/failure-$i', 500, i);
      }

      expect(buffer.entries.map((e) => e.line), hasLength(3));
      final report = buffer.export();
      expect(report.contains('failure-1'), isFalse);
      expect(report, contains('failure-2'));
      expect(report, contains('failure-4'));
    });

    test('export lists newest entries first', () {
      final buffer = DiagnosticsBuffer();

      buffer.recordRequest('GET', '/api/v1/oldest', 500, 1);
      buffer.recordRequest('GET', '/api/v1/newest', 500, 2);

      final report = buffer.export();
      expect(report.indexOf('newest'), lessThan(report.indexOf('oldest')));
    });

    test('clear empties the buffer', () {
      final buffer = DiagnosticsBuffer()..recordRequest('GET', '/x', 500, 1);

      buffer.clear();

      expect(buffer.isEmpty, isTrue);
      expect(buffer.export(), isEmpty);
    });

    test('the default capacity matches the issue contract', () {
      expect(DiagnosticsBuffer().capacity, 200);
    });
  });

  group('AppLogger integration', () {
    test('errors land in the diagnostics buffer', () {
      AppLogger.error('auth status stream failed', error: StateError('x'));

      final report = AppLogger.diagnosticsReport();
      expect(report, contains('auth status stream failed'));
      expect(report, contains('StateError'));
    });

    test('request helpers format the same records', () {
      AppLogger.request('GET', '/api/v1/articles', 429, 42);
      AppLogger.requestTimeout('POST', '/api/v1/auth/refresh', 10000);

      final report = AppLogger.diagnosticsReport();
      expect(report, contains('GET /api/v1/articles -> 429 (42ms)'));
      expect(
        report,
        contains('timeout POST /api/v1/auth/refresh (budget 10000ms)'),
      );
    });

    test('clearDiagnostics empties the report', () {
      AppLogger.error('something failed');
      AppLogger.clearDiagnostics();

      expect(AppLogger.diagnosticsReport(), isEmpty);
    });
  });
}
