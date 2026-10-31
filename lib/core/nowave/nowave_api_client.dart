import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;

/// Error returned by the no-wave REST API.
///
/// The backend answers every failure with
/// `{\"error\": {\"code\": \"...\", \"message\": \"...\"}}`; [code] is the stable
/// machine-readable identifier (e.g. `BAD_USER_INPUT`, `UNAUTHENTICATED`,
/// `RATE_LIMITED`) and [statusCode] the HTTP status. The message may be
/// English/technical: it is never rendered directly in the UI - it travels
/// in `cause` after [mapToServerException] converts this into a
/// display-safe [ServerException].
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

/// A media asset created by `POST /me/media`.
class NowaveMediaAsset {
  const NowaveMediaAsset({
    required this.id,
    required this.contentType,
    required this.byteSize,
    required this.width,
    required this.height,
  });

  final String id;
  final String contentType;
  final int byteSize;
  final int width;
  final int height;
}

/// Supplies and rotates the bearer token attached to authenticated
/// requests. Implemented by [NowaveSessionManager]; the client only ever
/// sees this narrow surface.
abstract class NowaveAuthenticator {
  /// Current access token, or null when signed out.
  String? get accessToken;

  /// Rotates the refresh token and updates the stored session.
  /// Single-flight: concurrent callers share one request (the backend
  /// revokes the whole session family when a rotated refresh token is
  /// reused, so a second concurrent refresh must never be issued).
  /// Returns true when a fresh access token is available.
  Future<bool> refresh();
}

/// Optional capability of an [NowaveAuthenticator]: rotate the access
/// token ahead of expiry instead of waiting for a 401.
///
/// The client awaits [ensureFreshAccess] before every authenticated
/// request; implementations must make the not-needed case a cheap,
/// throw-free time comparison.
abstract interface class NowaveProactiveAuthenticator
    implements NowaveAuthenticator {
  /// Returns true when a fresh access token is (still) available.
  Future<bool> ensureFreshAccess();
}

/// Optional identity fence for authenticators that can switch sessions.
/// Refreshing a token for the same session does not change the generation;
/// signing in, signing out, or replacing a session does.
abstract interface class NowaveSessionBoundAuthenticator
    implements NowaveAuthenticator {
  int get sessionGeneration;
}

/// Thin HTTP client for the no-wave `apps/api` REST surface (`/api/v1`).
///
/// Responsibilities:
/// - unwrap the `{data: ...}` envelope and throw [NowaveApiException] for
///   `{error: ...}` bodies (and for any other >= 400 response, so callers
///   never see a vague unparseable-payload error for server failures),
/// - attach the bearer token when signed in,
/// - transparently refresh an expired access token once on 401 and retry
///   the original request,
/// - bound the whole exchange - sending AND reading the response body -
///   with a timeout, so a stalled connection cannot hang a UI flow,
/// - upload raw image bytes to `POST /me/media` (the server re-encodes to
///   WebP; the returned URL is immutable).
///
/// Observability: every request is logged in debug builds with method,
/// path, status and duration. Headers, bodies and tokens are never logged.
///
/// Endpoint details verified against the no-wave `apps/api` source:
/// see docs/supabase-to-nowave-migration.md.
class NowaveApiClient {
  NowaveApiClient({
    required Uri baseUrl,
    NowaveAuthenticator? authenticator,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _baseUrl = _sanitizeBase(baseUrl),
       _basePrefix = _basePrefixOf(baseUrl),
       _authenticator = authenticator,
       _httpClient = httpClient ?? http.Client() {
    if (_basePrefix.endsWith(_kApiPrefix)) {
      // A base URL that already contains the versioned prefix would make
      // every request hit `/api/v1/api/v1/...` - a silent, total outage.
      // Fail fast with an actionable message instead.
      throw ArgumentError(
        'API_BASE_URL must not end with "$_kApiPrefix"; the client adds '
        'it itself. Got: $_baseUrl',
      );
    }
  }

  static const String _kApiPrefix = '/api/v1';

  /// Timeout applied to each phase of an exchange (send, body read) for
  /// JSON requests. Media uploads pass their own, longer budget.
  final Duration timeout;

  final Uri _baseUrl;
  final String _basePrefix;
  final NowaveAuthenticator? _authenticator;
  final http.Client _httpClient;

  /// Drops any query or fragment a configured base URL may carry; request
  /// queries are composed per call and a stray fragment would corrupt them.
  ///
  /// Rebuilding via string surgery + reparse (instead of the Uri
  /// constructor) keeps the exact original authority: an implicit default
  /// port stays implicit and an explicit one survives verbatim.
  static Uri _sanitizeBase(Uri url) {
    if (!url.hasQuery && !url.hasFragment) return url;
    var cleaned = url.toString();
    final queryAt = cleaned.indexOf('?');
    if (queryAt >= 0) cleaned = cleaned.substring(0, queryAt);
    final fragmentAt = cleaned.indexOf('#');
    if (fragmentAt >= 0) cleaned = cleaned.substring(0, fragmentAt);
    return Uri.parse(cleaned);
  }

  static String _basePrefixOf(Uri url) {
    final path = url.path;
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  /// Immutable public URL of an uploaded media asset.
  ///
  /// Built from the verified route `GET /api/v1/media/:id`. (The `src`
  /// field returned by the upload endpoint misses the `/v1` segment - an
  /// upstream inconsistency - so the URL is always constructed here.)
  Uri mediaUri(String id) => _resolveUri('$_kApiPrefix/media/$id');

  Uri _resolveUri(String path, [Map<String, String>? query]) {
    return _baseUrl.replace(
      path: '$_basePrefix$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  /// GET a JSON endpoint and return its unwrapped `data` payload.
  Future<dynamic> getJson(String path, {Map<String, String>? query}) {
    return _request('GET', path, query: query);
  }

  /// POST a JSON body; returns the unwrapped `data` payload.
  ///
  /// Set [authenticate] to false for the `/auth/*` endpoints, which take
  /// credentials in the body and must never trigger the refresh pipeline.
  Future<dynamic> postJson(
    String path,
    Object? body, {
    Map<String, String>? query,
    bool authenticate = true,
    Map<String, String>? extraHeaders,
  }) {
    return _request(
      'POST',
      path,
      query: query,
      body: body,
      authenticate: authenticate,
      extraHeaders: extraHeaders,
    );
  }

  /// PUT a JSON body; returns the unwrapped `data` payload.
  Future<dynamic> putJson(
    String path,
    Object? body, {
    bool authenticate = true,
  }) {
    return _request('PUT', path, body: body, authenticate: authenticate);
  }

  /// DELETE an endpoint; returns the unwrapped `data` payload when present.
  Future<dynamic> deleteJson(String path) => _request('DELETE', path);

  /// Uploads raw image bytes to `POST /me/media`.
  ///
  /// [contentType] is the picked file's MIME type; the server validates and
  /// re-encodes the image to WebP regardless of the input format. The
  /// upload gets a longer timeout budget than JSON calls.
  Future<NowaveMediaAsset> uploadMedia(
    Uint8List bytes,
    String contentType,
  ) async {
    final data = await _request(
      'POST',
      '$_kApiPrefix/me/media',
      rawBody: bytes,
      contentType: contentType,
      timeout: const Duration(seconds: 90),
    );
    final map = _asMap(data, 'media asset');
    return NowaveMediaAsset(
      id: map['id'] as String,
      contentType: map['contentType'] as String? ?? 'image/webp',
      byteSize: (map['byteSize'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Uint8List? rawBody,
    String? contentType,
    Map<String, String>? query,
    bool authenticate = true,
    bool allowRefresh = true,
    Duration? timeout,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = path.startsWith(_kApiPrefix)
        ? _resolveUri(path, query)
        : _resolveUri('$_kApiPrefix$path', query);

    http.Response response;
    if (!authenticate || _authenticator == null) {
      final headers = _headers(
        body: body,
        rawBody: rawBody,
        contentType: contentType,
      )..addAll(extraHeaders ?? const {});
      response = await _send(
        method,
        uri,
        headers,
        rawBody ?? (body == null ? null : jsonEncode(body)),
        timeout: timeout,
      );
    } else {
      final authenticator = _authenticator;
      final bound = authenticator is NowaveSessionBoundAuthenticator
          ? authenticator
          : null;
      final generation = bound?.sessionGeneration;

      void ensureSameSession() {
        if (bound != null && bound.sessionGeneration != generation) {
          // A write may already have committed under the old account. Do not
          // replay it with the new account or present the old response as new.
          throw const NowaveApiException(
            statusCode: HttpStatus.conflict,
            code: 'SESSION_CHANGED',
            message: 'Session changed while a request was in flight.',
          );
        }
      }

      Future<http.Response> sendForSession(Map<String, String> headers) async {
        try {
          return await _send(
            method,
            uri,
            headers,
            rawBody ?? (body == null ? null : jsonEncode(body)),
            timeout: timeout,
          );
        } finally {
          // Applies to both responses and transport errors.
          ensureSameSession();
        }
      }

      if (authenticator is NowaveProactiveAuthenticator) {
        await authenticator.ensureFreshAccess();
        ensureSameSession();
      }
      final sentToken = authenticator.accessToken;
      final headers = _headers(
        body: body,
        rawBody: rawBody,
        contentType: contentType,
        token: sentToken,
      )..addAll(extraHeaders ?? const {});
      response = await sendForSession(headers);
      if (response.statusCode == HttpStatus.unauthorized &&
          allowRefresh &&
          sentToken != null) {
        // Another request may already have refreshed the same session while
        // this response was in flight. Reuse that token instead of rotating
        // the same family again. Without an identity fence, fail closed if
        // the token changed because it might belong to a different account.
        var refreshed =
            bound != null &&
            authenticator.accessToken != null &&
            authenticator.accessToken != sentToken;
        if (!refreshed && authenticator.accessToken == sentToken) {
          AppLogger.debug('401 from $method ${uri.path}; refreshing session');
          refreshed = await authenticator.refresh();
          ensureSameSession();
        }
        if (refreshed && authenticator.accessToken != null) {
          final headers = _headers(
            body: body,
            rawBody: rawBody,
            contentType: contentType,
            token: authenticator.accessToken,
          )..addAll(extraHeaders ?? const {});
          response = await sendForSession(headers);
        } else {
          AppLogger.debug(
            'session refresh failed; surfacing the 401 from $method'
            ' ${uri.path}',
          );
        }
      }
    }
    return _decode(method, uri, response);
  }

  Map<String, String> _headers({
    Object? body,
    Uint8List? rawBody,
    String? contentType,
    String? token,
  }) {
    return <String, String>{
      'user-agent': 'belog-app/1.0',
      if (rawBody != null)
        'content-type': contentType ?? 'application/octet-stream'
      else if (body != null)
        'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? payload, {
    Duration? timeout,
  }) async {
    final budget = timeout ?? this.timeout;
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (payload is Uint8List) {
      request.bodyBytes = payload;
    } else if (payload is String) {
      request.body = payload;
    }
    final stopwatch = Stopwatch()..start();
    try {
      // The timeout covers both phases of the exchange: sending the
      // request and draining the response body. `fromStream` otherwise
      // has no bound at all and a stalled server could hang the caller.
      final streamed = await _httpClient.send(request).timeout(budget);
      final response = await http.Response.fromStream(streamed).timeout(budget);
      AppLogger.debug(
        '$method ${uri.path} -> ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      if (response.statusCode >= HttpStatus.badRequest) {
        // Release-build observability (issue #49): path and status only,
        // never the query string, headers or body.
        AppLogger.request(
          method,
          uri.path,
          response.statusCode,
          stopwatch.elapsedMilliseconds,
        );
      }
      return response;
    } on TimeoutException {
      AppLogger.debug(
        '$method ${uri.path} timed out after ${budget.inMilliseconds}ms',
      );
      AppLogger.requestTimeout(method, uri.path, budget.inMilliseconds);
      throw TimeoutException(
        '$method ${uri.path} did not answer within '
        '${budget.inMilliseconds}ms',
        budget,
      );
    } on SocketException {
      // Release-build observability (issue #49): "no network" is the most
      // common support case - it must not leave the diagnostics buffer
      // empty. The record keeps method and path; the error type says what
      // happened, never the error's text.
      AppLogger.requestUnreachable(method, uri.path, 'SocketException');
      rethrow;
    } on HttpException {
      AppLogger.requestUnreachable(method, uri.path, 'HttpException');
      rethrow;
    } on http.ClientException {
      AppLogger.requestUnreachable(method, uri.path, 'ClientException');
      rethrow;
    }
  }

  dynamic _decode(String method, Uri uri, http.Response response) {
    final String rawBody;
    try {
      rawBody = utf8.decode(response.bodyBytes);
    } on FormatException {
      AppLogger.responseMalformed(
        method,
        uri.path,
        response.statusCode,
        'non-utf8',
      );
      throw NowaveApiException(
        statusCode: response.statusCode,
        code: 'HTTP_${response.statusCode}',
        message: 'Unexpected non-UTF-8 response from $method $uri.',
      );
    }
    final dynamic body;
    try {
      body = rawBody.isEmpty ? null : jsonDecode(rawBody);
    } on FormatException {
      AppLogger.responseMalformed(
        method,
        uri.path,
        response.statusCode,
        'non-json',
      );
      throw NowaveApiException(
        statusCode: response.statusCode,
        code: 'HTTP_${response.statusCode}',
        message: 'Unexpected non-JSON response from $method $uri.',
      );
    }
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        throw NowaveApiException(
          statusCode: response.statusCode,
          code: error['code'] as String? ?? 'UNKNOWN',
          message: error['message'] as String? ?? 'The request failed.',
          retryAfterSeconds: int.tryParse(
            response.headers['retry-after'] ?? '',
          ),
        );
      }
      if (response.statusCode >= 400) {
        // A 4xx/5xx body that is not the documented error envelope: treat
        // it as a server failure instead of returning a null `data` payload
        // that callers would report as an unparseable response.
        throw NowaveApiException(
          statusCode: response.statusCode,
          code: 'HTTP_${response.statusCode}',
          message:
              'Unexpected error response shape from $method $uri: '
              '${body.keys.join(',')}',
        );
      }
      return body['data'];
    }
    if (response.statusCode >= 400) {
      throw NowaveApiException(
        statusCode: response.statusCode,
        code: 'HTTP_${response.statusCode}',
        message: 'Unexpected non-JSON error response from $method $uri.',
      );
    }
    return body;
  }

  Map<String, dynamic> _asMap(dynamic data, String what) {
    if (data is Map<String, dynamic>) return data;
    throw FormatException('Unexpected $what payload: $data');
  }
}
