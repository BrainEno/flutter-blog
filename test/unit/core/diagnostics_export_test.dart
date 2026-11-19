import 'dart:io';

import 'package:belog/core/utils/diagnostics_buffer.dart';
import 'package:belog/core/utils/diagnostics_file_export.dart';
import 'package:belog/core/utils/diagnostics_header.dart';
import 'package:belog/core/utils/diagnostics_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

/// An error object whose text embeds everything that must never reach an
/// exported diagnostics file.
class _BoobyTrappedError implements Exception {
  @override
  String toString() =>
      'token=secret-token user=user@example.invalid password=hunter2';
}

/// A deterministic clock the buffer and the exporter can share.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;
}

String _header() => buildDiagnosticsHeader(
  appName: 'belog',
  version: '0.2.0+1',
  buildMode: 'release',
  operatingSystem: 'android',
  osVersion: '15',
  locale: 'zh_CN',
  apiOrigin: 'api origin: https://api.example.invalid (https)',
);

void main() {
  group('composeDiagnosticsExport', () {
    test('carries version, origin and the newest probe/request records', () {
      final clock = _Clock(DateTime.utc(2026, 11, 19, 8));
      final buffer = DiagnosticsBuffer(clock: clock.call)
        ..recordProbeInconclusive('/api/v1/health', 3001, 3000);
      clock.now = clock.now.add(const Duration(seconds: 5));
      buffer.recordRequest('GET', '/api/v1/articles', 503, 1203);

      final document = composeDiagnosticsExport(
        header: _header(),
        entries: buffer.entries,
        generatedAt: DateTime.utc(2026, 11, 19, 8, 1),
      );

      expect(document, startsWith('No Wave diagnostics export\n'));
      expect(document, contains('format $kDiagnosticsExportFormat'));
      expect(document, contains('generated 2026-11-19T08:01:00.000Z'));
      expect(document, contains('nothing is uploaded automatically'));
      expect(document, contains('app belog 0.2.0+1'));
      expect(document, contains('build release'));
      expect(
        document,
        contains('api origin: https://api.example.invalid (https)'),
      );
      expect(document, contains('records 2 of 2'));
      expect(document, contains('window 24h'));
      expect(document, contains('probe GET /api/v1/health inconclusive'));
      expect(document, contains('request GET /api/v1/articles -> 503'));
      // Newest first, like the on-screen report.
      expect(
        document.indexOf('/api/v1/articles'),
        lessThan(document.indexOf('/api/v1/health')),
      );
      expect(document, endsWith('\n'));
    });

    test('keeps only the newest records up to the cap', () {
      final buffer = DiagnosticsBuffer();
      for (var i = 1; i <= 5; i++) {
        buffer.recordRequest('GET', '/api/v1/failure-$i', 500, i);
      }

      final document = composeDiagnosticsExport(
        header: _header(),
        entries: buffer.entries,
        generatedAt: DateTime.utc(2026, 11, 19),
        maxEntries: 2,
      );

      expect(document, contains('records 2 of 5'));
      expect(document, contains('cap 2'));
      expect(document, contains('failure-5'));
      expect(document, contains('failure-4'));
      expect(document.contains('failure-3'), isFalse);
      expect(document.contains('failure-1'), isFalse);
    });

    test('an empty window says so instead of exporting a blank file', () {
      final document = composeDiagnosticsExport(
        header: _header(),
        entries: const [],
        generatedAt: DateTime.utc(2026, 11, 19),
      );

      expect(document, contains('records 0 of 0'));
      expect(document, contains('(no failures recorded in this window)'));
    });

    test('never contains tokens, passwords or e-mail addresses', () {
      final buffer = DiagnosticsBuffer()
        ..recordError('refreshing the session failed', _BoobyTrappedError())
        // A misbehaving caller that embeds secrets in the static message.
        ..recordError(
          'sign-in for user@example.invalid failed password=hunter2 '
          'Authorization: Bearer abc.def.ghi',
          null,
        )
        ..recordRequest('GET', '/api/v1/articles?token=secret-token', 401, 12);

      final document = composeDiagnosticsExport(
        header: _header(),
        entries: buffer.entries,
        generatedAt: DateTime.utc(2026, 11, 19),
      );

      expect(document.contains('secret-token'), isFalse);
      expect(document.contains('hunter2'), isFalse);
      expect(document.contains('user@example.invalid'), isFalse);
      expect(document.contains('abc.def.ghi'), isFalse);
      // The useful parts of each record survive the redaction.
      expect(document, contains('refreshing the session failed'));
      expect(document, contains('_BoobyTrappedError'));
      expect(document, contains('GET /api/v1/articles -> 401 (12ms)'));
    });

    test('the window line describes non-hour windows in minutes', () {
      expect(describeDiagnosticsWindow(const Duration(hours: 24)), '24h');
      expect(describeDiagnosticsWindow(const Duration(minutes: 90)), '90m');
      expect(describeDiagnosticsWindow(const Duration(seconds: 30)), '30s');
    });
  });

  group('redactDiagnosticsText', () {
    test('masks credentials in every common spelling', () {
      const samples = {
        'token=abc123': 'token=<redacted>',
        'access_token: "abc 123"': 'access_token: <redacted>',
        'refresh_token=abc&x=1': 'refresh_token=<redacted>&x=1',
        'planToken=opaque-plan': 'planToken=<redacted>',
        'PASSWORD = hunter2': 'PASSWORD = <redacted>',
        'api_key=k-1': 'api_key=<redacted>',
        'Cookie: sid=1': 'Cookie: <redacted>',
        'Bearer abc.def': 'Bearer <redacted>',
      };
      samples.forEach((input, expected) {
        expect(redactDiagnosticsText(input), expected, reason: input);
      });
    });

    test('masks e-mail addresses and bare JWTs', () {
      expect(
        redactDiagnosticsText('reader user.name+tag@example.co.uk failed'),
        'reader <redacted-email> failed',
      );
      expect(
        redactDiagnosticsText('got eyJhbGciOi.eyJzdWIiOiIx.c2lnbmF0dXJl'),
        'got <redacted-token>',
      );
    });

    test('leaves the fixed report vocabulary untouched', () {
      const report =
          '2026-11-19T08:00:00.000 request GET /api/v1/articles -> 503 '
          '(1203ms)\n'
          '2026-11-19T08:00:01.000 timeout POST /api/v1/auth/refresh '
          '(budget 10000ms)\n'
          '2026-11-19T08:00:02.000 probe GET /api/v1/health inconclusive '
          '(TimeoutException after 3001ms, budget 3000ms)\n'
          'api origin: https://api.example.invalid (https)\n'
          'error refreshing the session failed (StateError)';

      expect(redactDiagnosticsText(report), report);
    });
  });

  group('DiagnosticsFileExporter', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('belog-diagnostics-test-');
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test(
      'writes the reviewed text and hands that file to the share sheet',
      () async {
        final shared = <XFile>[];
        final titles = <String>[];
        final exporter = DiagnosticsFileExporter(
          temporaryDirectory: () async => temp,
          share: (file, title) async {
            shared.add(file);
            titles.add(title);
          },
          clock: () => DateTime(2026, 11, 19, 8, 5, 9),
        );

        await exporter.exportAndShare(
          report: 'No Wave diagnostics export\n',
          shareTitle: 'No Wave diagnostics',
        );

        expect(shared, hasLength(1));
        expect(titles.single, 'No Wave diagnostics');
        expect(shared.single.mimeType, DiagnosticsFileExporter.mimeType);
        final file = File(shared.single.path);
        expect(
          file.path.endsWith('nowave-diagnostics-20261119-080509.txt'),
          isTrue,
        );
        expect(file.readAsStringSync(), 'No Wave diagnostics export\n');
      },
    );

    test('removes earlier exports but leaves unrelated files alone', () async {
      final stale = File(
        '${temp.path}${Platform.pathSeparator}'
        'nowave-diagnostics-20261118-010101.txt',
      )..writeAsStringSync('old');
      final unrelated = File(
        '${temp.path}${Platform.pathSeparator}belog-export-20261118.json',
      )..writeAsStringSync('{}');
      final exporter = DiagnosticsFileExporter(
        temporaryDirectory: () async => temp,
        share: (_, _) async {},
        clock: () => DateTime(2026, 11, 19, 9),
      );

      final written = await exporter.writeReport('new');

      expect(stale.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
      expect(written.readAsStringSync(), 'new');
      final exports = temp
          .listSync()
          .whereType<File>()
          .map((file) => file.path.split(Platform.pathSeparator).last)
          .where(DiagnosticsFileExporter.isExportFileName)
          .toList();
      expect(exports, ['nowave-diagnostics-20261119-090000.txt']);
    });

    test('a share failure propagates so the page can tell the user', () async {
      final exporter = DiagnosticsFileExporter(
        temporaryDirectory: () async => temp,
        share: (_, _) async => throw StateError('no share target'),
      );

      await expectLater(
        exporter.exportAndShare(report: 'x', shareTitle: 't'),
        throwsStateError,
      );
    });

    test('file names are stable and recognisable', () {
      expect(
        DiagnosticsFileExporter.fileNameFor(DateTime(2026, 1, 2, 3, 4, 5)),
        'nowave-diagnostics-20260102-030405.txt',
      );
      expect(
        DiagnosticsFileExporter.isExportFileName(
          'nowave-diagnostics-20260102-030405.txt',
        ),
        isTrue,
      );
      expect(
        DiagnosticsFileExporter.isExportFileName('belog-export-1.json'),
        isFalse,
      );
    });
  });
}
