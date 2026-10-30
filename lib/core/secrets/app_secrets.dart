class AppSecrets {
  /// Origin of the no-wave `apps/api` backend (e.g. https://api.example.com).
  /// The REST surface lives under `/api/v1`; no client key is needed.
  static String? get apiBaseUrl => String.fromEnvironment('API_BASE_URL');

  /// Origin of the no-wave `apps/web` deployment that serves the public
  /// article pages (issue #21). The web app is a separate origin from the
  /// API, so the canonical share URL cannot be derived from [apiBaseUrl].
  /// Empty until the deployment configures it; the share entry stays
  /// hidden rather than sharing a link that cannot open.
  static String? get webBaseUrl => String.fromEnvironment('WEB_BASE_URL');
}
