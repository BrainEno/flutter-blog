/// Configuration injected at build time with `--dart-define` or
/// `--dart-define-from-file` (see env.example.json).
///
/// The lookups below must stay `const` fields: `String.fromEnvironment` is a
/// const constructor and only guarantees the compiled value in a const
/// context. A non-const call returns the default (empty) string wherever the
/// platform has no runtime access to the compiler options - which is how a
/// correctly filled env.json still produced "API base URL not configured" on
/// Android. `test/unit/core/app_secrets_define_test.dart` pins this contract.
class AppSecrets {
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _webBaseUrl = String.fromEnvironment('WEB_BASE_URL');

  /// Origin of the no-wave `apps/api` backend (e.g. https://api.example.com).
  /// The REST surface lives under `/api/v1`; no client key is needed.
  static String? get apiBaseUrl => _apiBaseUrl.isEmpty ? null : _apiBaseUrl;

  /// Origin of the no-wave `apps/web` deployment that serves the public
  /// article pages (issue #21). The web app is a separate origin from the
  /// API, so the canonical share URL cannot be derived from [apiBaseUrl].
  /// It is also the only origin site-relative article resources and avatars
  /// (`/avatars/me.webp`, issue #63) may be resolved against.
  /// Empty until the deployment configures it; the share entry stays
  /// hidden rather than sharing a link that cannot open.
  static String? get webBaseUrl => _webBaseUrl.isEmpty ? null : _webBaseUrl;
}
