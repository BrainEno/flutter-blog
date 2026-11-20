/// Validates the compiled-in `API_BASE_URL` before anything uses it.
///
/// The value is a build-time define, so a missing or malformed origin is a
/// configuration mistake that no retry can fix. Failing here - with the exact
/// command that fixes it - is what lets the startup failure screen show a
/// useful message instead of every request failing later with a URL error.
///
/// Throws [StateError] when [value] is missing, empty, not an absolute
/// HTTP(S) URL, or carries a query or fragment.
Uri parseApiBaseUrlSetting(String? value) {
  if (value == null || value.isEmpty) {
    throw StateError(
      'API base URL not configured. '
      'Set API_BASE_URL via --dart-define-from-file=env.json or '
      '--dart-define=API_BASE_URL=... '
      'See env.example.json for template.',
    );
  }

  // Validate URL format (scheme + authority, no query or fragment).
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw StateError(
      'Invalid API_BASE_URL: "$value". Must be a valid HTTP(S) origin '
      '(e.g., https://api.example.com) without a query or fragment.',
    );
  }
  return uri;
}
