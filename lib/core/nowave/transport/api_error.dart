/// Error returned by the no-wave REST API.
///
/// The backend answers every failure with
/// `{"error": {"code": "...", "message": "..."}}`; [code] is the stable
/// machine-readable identifier (e.g. `BAD_USER_INPUT`, `UNAUTHENTICATED`,
/// `RATE_LIMITED`) and [statusCode] the HTTP status. The message may be
/// English/technical: it is never rendered directly in the UI - it travels
/// in `cause` after `mapToServerException` converts this into a
/// display-safe `ServerException`.
class NowaveApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  /// Parsed `Retry-After` header, only set for `RATE_LIMITED` responses.
  final int? retryAfterSeconds;

  const NowaveApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.retryAfterSeconds,
  });

  @override
  String toString() =>
      'NowaveApiException($statusCode $code: $message'
      '${retryAfterSeconds == null ? '' : ', retry after ${retryAfterSeconds}s'})';
}
