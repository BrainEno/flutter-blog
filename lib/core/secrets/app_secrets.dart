class AppSecrets {
  /// Origin of the no-wave `apps/api` backend (e.g. https://api.example.com).
  /// The REST surface lives under `/api/v1`; no client key is needed.
  static String? get apiBaseUrl => String.fromEnvironment('API_BASE_URL');
}
