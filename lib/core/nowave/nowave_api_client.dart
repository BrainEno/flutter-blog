import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Error returned by the no-wave REST API.
///
/// The backend answers every failure with
/// `{"error": {"code": "...", "message": "..."}}`; [code] is the stable
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
      '${retryAfterSeconds == null ? '' : ', retryAfter ${retryAfterSeconds}s'})';
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

/// Thin HTTP client for the no-wave `apps/api` REST surface (`/api/v1`).
///
/// Responsibilities:
/// - unwrap the `{data: ...}` envelope and throw [NowaveApiException] for
///   `{error: ...}` bodies,
/// - attach the bearer token when signed in,
/// - transparently refresh an expired access token once on 401 and retry
///   the original request,
/// - upload raw image bytes to `POST /me/media` (the server re-encodes to
///   WebP; the returned URL is immutable).
///
/// Endpoint details verified against the no-wave `apps/api` source:
/// see docs/supabase-to-nowave-migration.md.
class NowaveApiClient {
  NowaveApiClient({
    required Uri baseUrl,
    NowaveAuthenticator? authenticator,
    http.Client? httpClient,
  }) : _baseUrl = baseUrl,
       _basePrefix = baseUrl.path.endsWith('/')
           ? baseUrl.path.substring(0, baseUrl.path.length - 1)
           : baseUrl.path,
       _authenticator = authenticator,
       _httpClient = httpClient ?? http.Client();

  static const String _kApiPrefix = '/api/v1';

  final Uri _baseUrl;
  final String _basePrefix;
  final NowaveAuthenticator? _authenticator;
  final http.Client _httpClient;

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
    bool authenticate = true,
  }) {
    return _request('POST', path, body: body, authenticate: authenticate);
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
  /// re-encodes the image to WebP regardless of the input format.
  Future<NowaveMediaAsset> uploadMedia(
    Uint8List bytes,
    String contentType,
  ) async {
    final data = await _request(
      'POST',
      '$_kApiPrefix/me/media',
      rawBody: bytes,
      contentType: contentType,
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
  }) async {
    final uri = path.startsWith(_kApiPrefix)
        ? _resolveUri(path, query)
        : _resolveUri('$_kApiPrefix$path', query);

    http.Response response;
    if (!authenticate || _authenticator == null) {
      response = await _send(
        method,
        uri,
        _headers(body: body, rawBody: rawBody, contentType: contentType),
        rawBody ?? (body == null ? null : jsonEncode(body)),
      );
    } else {
      // Attach the bearer token; a 401 rotates the access token exactly
      // once (a failed refresh - revoked session family - leaves the 401
      // for the caller to map).
      response = await _send(
        method,
        uri,
        _headers(
          body: body,
          rawBody: rawBody,
          contentType: contentType,
          token: _authenticator.accessToken,
        ),
        rawBody ?? (body == null ? null : jsonEncode(body)),
      );
      if (response.statusCode == HttpStatus.unauthorized &&
          allowRefresh &&
          _authenticator.accessToken != null) {
        final refreshed = await _authenticator.refresh();
        if (refreshed) {
          response = await _send(
            method,
            uri,
            _headers(
              body: body,
              rawBody: rawBody,
              contentType: contentType,
              token: _authenticator.accessToken,
            ),
            rawBody ?? (body == null ? null : jsonEncode(body)),
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
    Object? payload,
  ) async {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (payload is Uint8List) {
      request.bodyBytes = payload;
    } else if (payload is String) {
      request.body = payload;
    }
    final streamed = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    return http.Response.fromStream(streamed);
  }

  dynamic _decode(String method, Uri uri, http.Response response) {
    final String rawBody;
    try {
      rawBody = utf8.decode(response.bodyBytes);
    } on FormatException {
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
