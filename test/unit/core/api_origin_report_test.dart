import 'package:belog/core/network/api_origin_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line as the console and the diagnostics header show it.
String _line(String configured, {required bool debugBuild}) =>
    describeApiOrigin(Uri.parse(configured), debugBuild: debugBuild);

void main() {
  group('describeApiOrigin', () {
    test('https needs no caveat', () {
      expect(
        _line('https://api.example.invalid', debugBuild: false),
        'api origin: https://api.example.invalid (https)',
      );
    });

    test('a debug build says plain HTTP is allowed', () {
      expect(
        _line('http://10.0.2.2:4000', debugBuild: true),
        'api origin: http://10.0.2.2:4000 '
        '(http, debug build allows cleartext)',
      );
    });

    test('a release build names the cleartext block', () {
      // The case behind most "it cannot connect" reports: the origin is right
      // and the platform still refuses the request.
      final line = _line('http://10.0.2.2:4000', debugBuild: false);
      expect(line, contains('http://10.0.2.2:4000'));
      expect(line, contains('block cleartext'));
    });

    test('an explicit port survives, an implicit one is not invented', () {
      expect(
        _line('https://api.example.invalid', debugBuild: true),
        isNot(contains(':443')),
      );
      expect(
        _line('https://api.example.invalid:8443', debugBuild: true),
        contains(':8443'),
      );
    });

    test('a configured path prefix is kept, the trailing slash is not', () {
      expect(
        _line('https://host.invalid/nowave/', debugBuild: true),
        'api origin: https://host.invalid/nowave (https)',
      );
    });

    test('never prints userinfo, query or fragment', () {
      final line = describeApiOrigin(
        Uri.parse('https://user:secret@host.invalid/api?token=abc#frag'),
        debugBuild: true,
      );
      expect(line, 'api origin: https://host.invalid/api (https)');
      expect(line.contains('secret'), isFalse);
      expect(line.contains('token'), isFalse);
      expect(line.contains('user'), isFalse);
    });

    test('an IPv6 host stays bracketed', () {
      expect(
        _line('http://[::1]:4000', debugBuild: true),
        contains('http://[::1]:4000'),
      );
    });
  });
}
