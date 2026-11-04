/// The configured API origin plus the versioned prefix every request shares.
///
/// Kept separate from the client so the URL rules - which are easy to break
/// silently and cheap to test - are one small unit: the versioned `/api/v1`
/// segment is added exactly once, a stray query or fragment must not corrupt
/// per-call queries, the configured path is preserved, and a base URL that
/// already carries `/api/v1` is rejected instead of producing
/// `/api/v1/api/v1/...` for every request.
class ApiBaseUrl {
  /// Parses and validates [url].
  ///
  /// Throws [ArgumentError] when [url] already ends with [apiPrefix].
  factory ApiBaseUrl.parse(Uri url) {
    final sanitized = _sanitize(url);
    if (_pathPrefixOf(url).endsWith(apiPrefix)) {
      throw ArgumentError(
        'API_BASE_URL must not end with "$apiPrefix"; the client adds '
        'it itself. Got: $sanitized',
      );
    }
    return ApiBaseUrl._(sanitized, _pathPrefixOf(url));
  }

  const ApiBaseUrl._(this.base, this.pathPrefix);

  /// The versioned segment [resolve] adds to a relative path.
  static const String apiPrefix = '/api/v1';

  /// Origin (and optional path) without query or fragment.
  final Uri base;

  /// [base]'s path without a trailing slash; prepended to every request path.
  final String pathPrefix;

  /// Immutable public URL of an uploaded media asset.
  ///
  /// Built from the verified route `GET /api/v1/media/:id`. (The `src`
  /// field returned by the upload endpoint misses the `/v1` segment - an
  /// upstream inconsistency - so the URL is always constructed here.)
  Uri mediaUri(String id) => resolve('/media/$id');

  /// Composes [path] - relative to the versioned API root - with an optional
  /// query.
  ///
  /// A [path] that already starts with [apiPrefix] (a caller spelling out the
  /// version) is kept as is, so the segment can never be doubled.
  Uri resolve(String path, [Map<String, String>? query]) {
    return base.replace(
      path: '$pathPrefix${_withPrefix(path)}',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  /// Adds [apiPrefix] unless [path] already starts with it.
  static String _withPrefix(String path) {
    if (path == apiPrefix || path.startsWith('$apiPrefix/')) return path;
    return '$apiPrefix$path';
  }

  /// Drops any query or fragment a configured base URL may carry; request
  /// queries are composed per call and a stray fragment would corrupt them.
  ///
  /// Rebuilding via string surgery + reparse (instead of the Uri
  /// constructor) keeps the exact original authority: an implicit default
  /// port stays implicit and an explicit one survives verbatim.
  static Uri _sanitize(Uri url) {
    if (!url.hasQuery && !url.hasFragment) return url;
    var cleaned = url.toString();
    final queryAt = cleaned.indexOf('?');
    if (queryAt >= 0) cleaned = cleaned.substring(0, queryAt);
    final fragmentAt = cleaned.indexOf('#');
    if (fragmentAt >= 0) cleaned = cleaned.substring(0, fragmentAt);
    return Uri.parse(cleaned);
  }

  static String _pathPrefixOf(Uri url) {
    final path = url.path;
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
}
