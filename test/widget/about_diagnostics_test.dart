import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/user/presentation/pages/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Deterministic package info so the version row and the diagnostics
/// header are assertable in tests.
Future<PackageInfo> _fakePackageInfo() async => PackageInfo(
  appName: 'belog',
  packageName: 'com.example.belog',
  version: '9.9',
  buildNumber: '42',
);

/// An error whose text carries data that must never reach the dialog.
class _BoobyTrappedError implements Exception {
  @override
  String toString() => 'token=secret-token user=user@example.invalid';
}

void main() {
  setUp(AppLogger.clearDiagnostics);

  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: AboutPage(packageInfoLoader: _fakePackageInfo),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('long-pressing the version shows the sanitized diagnostics', (
    tester,
  ) async {
    await pumpAbout(tester);
    AppLogger.error(
      'refreshing the session failed',
      error: _BoobyTrappedError(),
    );
    AppLogger.request('GET', '/api/v1/articles', 503, 1203);

    await tester.longPress(find.text('应用版本: 9.9+42'));
    await tester.pumpAndSettle();

    expect(find.text('诊断信息'), findsOneWidget);
    final reportText = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    final report = reportText.data ?? '';
    // The sanitized context header leads the report (issue #49 follow-up).
    expect(report, contains('app belog 9.9+42'));
    expect(report, contains('build debug'));
    expect(report, contains('platform android'));
    expect(report, contains('locale zh'));
    expect(report, contains('refreshing the session failed'));
    expect(report, contains('GET /api/v1/articles -> 503'));
    // No credentials or personal data in what would be copied.
    expect(report.contains('secret-token'), isFalse);
    expect(report.contains('user@example.invalid'), isFalse);
  });

  testWidgets('the version row shows the real manifest version', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.text('应用版本: 9.9+42'), findsOneWidget);
    expect(find.textContaining('Version 1.9'), findsNothing);
  });

  testWidgets('an empty buffer explains itself instead of showing noise', (
    tester,
  ) async {
    await pumpAbout(tester);

    await tester.longPress(find.text('应用版本: 9.9+42'));
    await tester.pumpAndSettle();

    expect(find.textContaining('诊断缓冲为空'), findsOneWidget);
  });

  testWidgets('clearing the buffer empties the dialog on the spot', (
    tester,
  ) async {
    await pumpAbout(tester);
    AppLogger.request('GET', '/api/v1/articles', 500, 42);

    await tester.longPress(find.text('应用版本: 9.9+42'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GET /api/v1/articles'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.textContaining('诊断缓冲为空'), findsOneWidget);
    // The header survives the clear; only the records are gone.
    expect(find.textContaining('app belog 9.9+42'), findsOneWidget);
    expect(AppLogger.diagnosticsReport(), isEmpty);
  });

  testWidgets('sharing hands the reviewed text to the share sheet', (
    tester,
  ) async {
    await pumpAbout(tester);
    AppLogger.request('GET', '/api/v1/articles', 500, 42);

    await tester.longPress(find.text('应用版本: 9.9+42'));
    await tester.pumpAndSettle();
    expect(find.text('分享'), findsOneWidget);

    // Tapping closes the dialog and must not crash on surfaces without a
    // share target - copying stays available as the fallback.
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('诊断信息'), findsNothing);
    expect(AppLogger.diagnosticsReport(), isNotEmpty);
  });

  testWidgets('closing the dialog keeps the buffer intact', (tester) async {
    await pumpAbout(tester);
    AppLogger.request('GET', '/api/v1/articles', 500, 42);

    await tester.longPress(find.text('应用版本: 9.9+42'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.text('诊断信息'), findsNothing);
    expect(AppLogger.diagnosticsReport(), isNotEmpty);
  });
}
