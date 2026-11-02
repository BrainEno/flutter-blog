import 'package:belog/core/secrets/app_secrets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The value the tooling actually baked into this binary. Only a `const`
/// evaluation of `String.fromEnvironment` sees `--dart-define`; the SDK
/// documentation explicitly says "only guaranteed to work when invoked as
/// const".
const String _definedApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const String _definedWebBaseUrl = String.fromEnvironment('WEB_BASE_URL');

void main() {
  test('the API origin is read as a compile-time constant', () {
    // Run with `--dart-define-from-file=env.json` for this to be meaningful:
    // a non-const lookup returns the empty default there and would still
    // report "API base URL not configured" with a valid configuration file.
    expect(
      AppSecrets.apiBaseUrl,
      _definedApiBaseUrl.isEmpty ? isNull : _definedApiBaseUrl,
    );
    expect(
      AppSecrets.webBaseUrl,
      _definedWebBaseUrl.isEmpty ? isNull : _definedWebBaseUrl,
    );
  });

  test('an unset define is reported as missing, not as an empty origin', () {
    // The router and the startup guard treat null and '' the same way, but
    // callers trim and compare, so the contract stays nullable.
    if (_definedApiBaseUrl.isEmpty) {
      expect(AppSecrets.apiBaseUrl, isNull);
    }
  });
}
