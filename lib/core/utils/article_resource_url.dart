import 'package:belog/core/secrets/app_secrets.dart';

/// Validates the URL shapes accepted by no-wave article documents. Relative
/// paths belong to the web site, not the API origin. Unsafe URLs stay inert.
bool isValidArticleResourceUrl(String value) {
  if (value.isEmpty ||
      value.length > 2048 ||
      value != value.trim() ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value)) {
    return false;
  }
  if (value.startsWith('/')) return !value.startsWith('//');
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

/// Resolve only against an explicitly configured, valid WEB_BASE_URL. Never
/// infer the website origin from the API, as the two may be unrelated.
Uri? resolveArticleResourceUrl(String value, {String? webBaseUrl}) {
  if (!isValidArticleResourceUrl(value)) return null;
  if (!value.startsWith('/')) return Uri.tryParse(value);

  final base = webBaseUrl ?? AppSecrets.webBaseUrl;
  if (base == null || base.isEmpty || !isValidArticleResourceUrl(base)) {
    return null;
  }
  final baseUri = Uri.tryParse(base);
  if (baseUri == null || !baseUri.hasAuthority) return null;
  try {
    final resolved = baseUri.resolve(value);
    return resolved.origin == baseUri.origin ? resolved : null;
  } on FormatException {
    return null;
  }
}
