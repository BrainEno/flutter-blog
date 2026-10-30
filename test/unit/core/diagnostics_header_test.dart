import 'package:belog/core/utils/diagnostics_header.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('composes the coarse context lines support needs', () {
    final header = buildDiagnosticsHeader(
      appName: 'belog',
      version: '0.0.0+1',
      buildMode: 'release',
      operatingSystem: 'android',
      osVersion: '14',
      locale: 'zh',
    );

    expect(header, contains('app belog 0.0.0+1'));
    expect(header, contains('build release'));
    expect(header, contains('platform android (14)'));
    expect(header, contains('locale zh'));
    // Four context lines, one per field - nothing else rides along.
    expect(header.split('\n'), hasLength(4));
  });

  test('a missing OS version degrades without parentheses', () {
    final header = buildDiagnosticsHeader(
      appName: 'belog',
      version: '1.2.3+42',
      buildMode: 'debug',
      operatingSystem: 'ios',
      locale: 'en',
    );

    expect(header, contains('platform ios\n'));
    expect(header.contains('('), isFalse);
  });
}
