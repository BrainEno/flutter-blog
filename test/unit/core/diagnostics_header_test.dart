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

  test('the compiled API origin is appended when there is one', () {
    final header = buildDiagnosticsHeader(
      appName: 'belog',
      version: '0.2.0+1',
      buildMode: 'debug',
      operatingSystem: 'android',
      locale: 'zh',
      apiOrigin:
          'api origin: http://10.0.2.2:4000 '
          '(http, debug build allows cleartext)',
    );

    expect(header.split('\n'), hasLength(5));
    expect(
      header,
      contains(
        'api origin: http://10.0.2.2:4000 '
        '(http, debug build allows cleartext)',
      ),
    );
  });

  test('an unconfigured build adds no empty line', () {
    for (final apiOrigin in [null, '']) {
      final header = buildDiagnosticsHeader(
        appName: 'belog',
        version: '0.2.0+1',
        buildMode: 'release',
        operatingSystem: 'android',
        locale: 'zh',
        apiOrigin: apiOrigin,
      );
      expect(header.split('\n'), hasLength(4));
      expect(header.contains('api origin'), isFalse);
    }
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
