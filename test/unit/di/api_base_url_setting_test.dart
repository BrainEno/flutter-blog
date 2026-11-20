import 'package:belog/di/api_base_url_setting.dart';
import 'package:flutter_test/flutter_test.dart';

/// `API_BASE_URL` is compiled in, so a bad value can only be fixed by a new
/// build. The composition root refuses it up front with a message the startup
/// failure screen shows verbatim (`test/widget/startup_failure_app_test.dart`
/// pins the wording the screen matches on).
void main() {
  group('parseApiBaseUrlSetting accepts', () {
    for (final value in [
      'https://api.example.com',
      'https://api.example.com/',
      'http://10.0.2.2:4000',
      'http://localhost:3000',
      'https://example.com/nowave',
      'HTTPS://API.EXAMPLE.COM',
    ]) {
      test(value, () {
        final uri = parseApiBaseUrlSetting(value);
        expect(uri.hasAuthority, isTrue);
        expect(uri.scheme, anyOf('http', 'https'));
      });
    }

    test('and keeps the configured path for the client to extend', () {
      final uri = parseApiBaseUrlSetting('https://example.com/nowave');
      expect(uri.host, 'example.com');
      expect(uri.path, '/nowave');
    });
  });

  group('parseApiBaseUrlSetting refuses a missing value', () {
    for (final value in <String?>[null, '']) {
      test('${value == null ? 'null' : 'empty'} with setup instructions', () {
        expect(
          () => parseApiBaseUrlSetting(value),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => error.message,
                  'message',
                  startsWith('API base URL not configured. '),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('--dart-define-from-file=env.json'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('env.example.json'),
                ),
          ),
        );
      });
    }
  });

  group('parseApiBaseUrlSetting refuses a malformed origin', () {
    for (final value in [
      'api.example.com',
      'ftp://api.example.com',
      'file:///etc/hosts',
      'https://api.example.com?debug=1',
      'https://api.example.com#top',
      'mailto:owner@example.com',
      '::not a url::',
    ]) {
      test(value, () {
        expect(
          () => parseApiBaseUrlSetting(value),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                startsWith('Invalid API_BASE_URL: "$value".'),
                contains('without a query or fragment'),
              ),
            ),
          ),
        );
      });
    }
  });
}
