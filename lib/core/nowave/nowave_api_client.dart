import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/transport/api_base_url.dart';
import 'package:belog/core/nowave/transport/api_envelope.dart';
import 'package:belog/core/nowave/transport/api_error.dart';
import 'package:belog/core/nowave/transport/media_asset.dart';
import 'package:belog/core/nowave/transport/unauthorized_replay.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;

export 'package:belog/core/nowave/transport/api_error.dart';
export 'package:belog/core/nowave/transport/media_asset.dart';

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

/// Supplies the resolved server identity for viewer-scoped requests.
/// The identity is a local fence only; authorization remains server-side.
/// A viewer authenticator must also expose its session generation.
abstract interface class NowaveViewerAuthenticator
    implements NowaveSessionBoundAuthenticator {
  String? get activeUserId;
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
  }) : _base = ApiBaseUrl.parse(baseUrl),
       _authenticator = authenticator,
       _httpClient = httpClient ?? http.Client();

  /// Timeout applied to each phase of an exchange (send, body read) for
  /// JSON requests. Media uploads pass their own, longer budget.
  final Duration timeout;

  /// Origin, path prefix and URL composition rules ([ApiBaseUrl]): the
  /// versioned `/api/v1` segment is added in exactly one place, and a base URL
  /// that already ends with it is rejected there, so this client can never
  /// build `/api/v1/api/v1/...`.
  final ApiBaseUrl _base;

  final NowaveAuthenticator? _authenticator;
  final http.Client _httpClient;

  /// Immutable public URL of an uploaded media asset.
  Uri mediaUri(String id) => _base.mediaUri(id);

  /// GET a JSON endpoint and return its unwrapped `data` payload. Set
  /// [followRedirects] to false for private reads that must not forward an
  /// Authorization header to a redirect target; 3xx then fails closed.
  Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
    NowaveSessionFence? sessionFence,
    bool followRedirects = true,
  }) {
    return _request(
      'GET',
      path,
      query: query,
      sessionFence: sessionFence,
      followRedirects: followRedirects,
    );
  }

  /// Reads account-scoped data only for the identity that initiated the
  /// operation. This also fences the interval before [_request] starts and
  /// after it completes, when the UI's identity may lag a session switch.
  Future<dynamic> getJsonForViewer(
    String path, {
    required String expectedUserId,
    Map<String, String>? query,
  }) async {
    return (await getEnvelopeForViewer(
      path,
      expectedUserId: expectedUserId,
      query: query,
    )).data;
  }

  /// Like [getJsonForViewer], but keeps the envelope's `meta` object.
  ///
  /// The `meta` marker is the only way to tell a documented multi-language
  /// list from an older deployment that ignored the parameter and answered a
  /// single language: both are a 200 with a `data` array.
  Future<EnvelopeData> getEnvelopeForViewer(
    String path, {
    required String expectedUserId,
    Map<String, String>? query,
  }) async {
    final auth = _authenticator;
    if (auth is! NowaveViewerAuthenticator ||
        expectedUserId.isEmpty ||
        auth.activeUserId != expectedUserId ||
        (auth.accessToken?.isEmpty ?? true)) {
      throw const NowaveApiException(
        statusCode: HttpStatus.conflict,
        code: 'SESSION_CHANGED',
        message: 'The active session no longer matches the requested viewer.',
      );
    }
    final generation = auth.sessionGeneration;
    try {
      return await _requestEnvelope(
        'GET',
        path,
        query: query,
        // A private read must not carry its bearer token to a redirect target.
        followRedirects: false,
      );
    } finally {
      if (auth.sessionGeneration != generation ||
          auth.activeUserId != expectedUserId ||
          (auth.accessToken?.isEmpty ?? true)) {
        throw const NowaveApiException(
          statusCode: HttpStatus.conflict,
          code: 'SESSION_CHANGED',
          message: 'The active session changed during a viewer-scoped request.',
        );
      }
    }
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
    bool followRedirects = true,
    Map<String, String>? extraHeaders,
    NowaveSessionFence? sessionFence,
  }) {
    return _request(
      'POST',
      path,
      query: query,
      body: body,
      authenticate: authenticate,
      followRedirects: followRedirects,
      extraHeaders: extraHeaders,
      sessionFence: sessionFence,
    );
  }

  /// PUT a JSON body; returns the unwrapped `data` payload.
  Future<dynamic> putJson(
    String path,
    Object? body, {
    bool authenticate = true,
    NowaveSessionFence? sessionFence,
  }) {
    return _request(
      'PUT',
      path,
      body: body,
      authenticate: authenticate,
      sessionFence: sessionFence,
    );
  }

  /// PATCH a JSON body; private writes fail closed on redirects by default.
  Future<dynamic> patchJson(
    String path,
    Object? body, {
    bool authenticate = true,
    bool followRedirects = false,
    NowaveSessionFence? sessionFence,
  }) => _request(
    'PATCH',
    path,
    body: body,
    authenticate: authenticate,
    followRedirects: followRedirects,
    sessionFence: sessionFence,
  );

  /// Sends one sensitive, viewer-scoped PUT, with no 401 replay or redirect.
  ///
  /// A 401 can mean the submitted credential was rejected, not an expired
  /// access token. Replaying the write could consume another rate-limit slot.
  /// Redirects are disabled so credentials cannot be forwarded elsewhere.
  /// The caller's captured generation also prevents a form opened by an old
  /// session from being submitted after even a same-account re-login.
  Future<dynamic> putJsonForViewerOnce(
    String path,
    Object? body, {
    required String expectedUserId,
    required int expectedSessionGeneration,
  }) async {
    final auth = _authenticator;
    bool matches() =>
        auth is NowaveViewerAuthenticator &&
        expectedUserId.isNotEmpty &&
        auth.activeUserId == expectedUserId &&
        auth.sessionGeneration == expectedSessionGeneration &&
        (auth.accessToken?.isNotEmpty ?? false);

    void ensureSameViewer() {
      if (!matches()) {
        throw const NowaveApiException(
          statusCode: HttpStatus.conflict,
          code: 'SESSION_CHANGED',
          message: 'Session changed during a viewer-scoped write.',
        );
      }
    }

    ensureSameViewer();
    try {
      return await _request(
        'PUT',
        path,
        body: body,
        allowRefresh: false,
        followRedirects: false,
      );
    } finally {
      // The old write may have reached the server even on a transport error.
      ensureSameViewer();
    }
  }

  /// Sends one viewer-scoped POST, with no 401 replay or redirect.
  ///
  /// Same contract as [putJsonForViewerOnce]: a 401 on an endpoint that takes
  /// no credential of its own says the session is gone, not that a refresh
  /// would help, and replaying it would burn another rate-limit slot (or send a
  /// second mail). Redirects are off so nothing is forwarded to a new origin.
  Future<dynamic> postJsonForViewerOnce(
    String path,
    Object? body, {
    required String expectedUserId,
    required int expectedSessionGeneration,
  }) async {
    final auth = _authenticator;
    bool matches() =>
        auth is NowaveViewerAuthenticator &&
        expectedUserId.isNotEmpty &&
        auth.activeUserId == expectedUserId &&
        auth.sessionGeneration == expectedSessionGeneration &&
        (auth.accessToken?.isNotEmpty ?? false);

    void ensureSameViewer() {
      if (!matches()) {
        throw const NowaveApiException(
          statusCode: HttpStatus.conflict,
          code: 'SESSION_CHANGED',
          message: 'Session changed during a viewer-scoped write.',
        );
      }
    }

    ensureSameViewer();
    try {
      return await _request(
        'POST',
        path,
        body: body,
        allowRefresh: false,
        followRedirects: false,
      );
    } finally {
      // The request may have reached the server even on a transport error.
      ensureSameViewer();
    }
  }

  /// DELETE an endpoint; returns the unwrapped `data` payload when present.
  ///
  /// Set [followRedirects] to false for a private deletion: following a 3xx
  /// would forward the bearer token to another target, and the deletion may
  /// already have happened where it was first sent.
  Future<dynamic> deleteJson(
    String path, {
    NowaveSessionFence? sessionFence,
    bool followRedirects = true,
  }) => _request(
    'DELETE',
    path,
    sessionFence: sessionFence,
    followRedirects: followRedirects,
  );

  /// Uploads raw image bytes to `POST /me/media`.
  ///
  /// [contentType] is the picked file's MIME type; the server validates and
  /// re-encodes the image to WebP regardless of the input format. The
  /// upload gets a longer timeout budget than JSON calls.
  Future<NowaveMediaAsset> uploadMedia(
    Uint8List bytes,
    String contentType, {
    NowaveSessionFence? sessionFence,
  }) async {
    final data = await _request(
      'POST',
      '/me/media',
      rawBody: bytes,
      contentType: contentType,
      timeout: const Duration(seconds: 90),
      sessionFence: sessionFence,
    );
    return NowaveMediaAsset.fromDataMap(requireJsonMap(data, 'media asset'));
  }

  void _requireSessionFence(NowaveSessionFence fence) {
    final auth = _authenticator;
    if (auth is! NowaveViewerAuthenticator ||
        fence.userId.isEmpty ||
        auth.activeUserId != fence.userId ||
        auth.sessionGeneration != fence.generation ||
        (auth.accessToken?.isEmpty ?? true)) {
      throw const NowaveApiException(
        statusCode: HttpStatus.conflict,
        code: 'SESSION_CHANGED',
        message: 'The account that started this operation is no longer active.',
      );
    }
  }

  /// Runs one request and returns only the unwrapped `data` payload.
  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Uint8List? rawBody,
    String? contentType,
    Map<String, String>? query,
    bool authenticate = true,
    bool allowRefresh = true,
    bool followRedirects = true,
    Duration? timeout,
    Map<String, String>? extraHeaders,
    NowaveSessionFence? sessionFence,
  }) async {
    final envelope = await _requestEnvelope(
      method,
      path,
      body: body,
      rawBody: rawBody,
      contentType: contentType,
      query: query,
      authenticate: authenticate,
      allowRefresh: allowRefresh,
      followRedirects: followRedirects,
      timeout: timeout,
      extraHeaders: extraHeaders,
      sessionFence: sessionFence,
    );
    return envelope.data;
  }

  /// The transport itself: same request, same failures, full envelope back.
  Future<EnvelopeData> _requestEnvelope(
    String method,
    String path, {
    Object? body,
    Uint8List? rawBody,
    String? contentType,
    Map<String, String>? query,
    bool authenticate = true,
    bool allowRefresh = true,
    bool followRedirects = true,
    Duration? timeout,
    Map<String, String>? extraHeaders,
    NowaveSessionFence? sessionFence,
  }) async {
    if (sessionFence != null) {
      if (!authenticate) {
        throw ArgumentError('An identity fence requires authentication.');
      }
      _requireSessionFence(sessionFence);
    }
    final uri = _base.resolve(path, query);

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
        followRedirects: followRedirects,
      );
    } else {
      final authenticator = _authenticator;
      final bound = authenticator is NowaveSessionBoundAuthenticator
          ? authenticator
          : null;
      final generation = bound?.sessionGeneration;

      bool sessionEnded() =>
          bound != null &&
          bound.sessionGeneration != generation &&
          authenticator.accessToken == null;

      void ensureSameSession() {
        if (sessionFence != null) _requireSessionFence(sessionFence);
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
            followRedirects: followRedirects,
          );
        } finally {
          // Applies to both responses and transport errors.
          ensureSameSession();
        }
      }

      if (authenticator is NowaveProactiveAuthenticator) {
        await authenticator.ensureFreshAccess();
        if (sessionEnded()) {
          // No request has been sent yet. Preserve the ordinary expired-login
          // behavior instead of implying that a write might have committed.
          throw const NowaveApiException(
            statusCode: HttpStatus.unauthorized,
            code: 'UNAUTHENTICATED',
            message: 'Session expired before the request was sent.',
          );
        }
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
      if (response.statusCode == HttpStatus.unauthorized) {
        // One reaction at most, decided by a unit-tested rule
        // ([decideUnauthorizedReplay]): reuse a token another request already
        // rotated, refresh once, or fail closed and surface the 401.
        var replay = decideUnauthorizedReplay(
          sentToken: sentToken,
          currentToken: authenticator.accessToken,
          sessionBound: bound != null,
          allowRefresh: allowRefresh,
        );
        if (replay == UnauthorizedReplay.refreshFirst) {
          AppLogger.debug('401 from $method ${uri.path}; refreshing session');
          final refreshed = await authenticator.refresh();
          // If refresh ended the session, preserve the definitive original
          // 401 and never retry. A replacement account still fails the fence.
          if (!sessionEnded()) ensureSameSession();
          final current = authenticator.accessToken;
          replay = refreshed && current != null
              ? UnauthorizedReplay.reuseCurrentToken
              : UnauthorizedReplay.surfaceOriginal;
        }
        if (replay == UnauthorizedReplay.reuseCurrentToken) {
          final headers = _headers(
            body: body,
            rawBody: rawBody,
            contentType: contentType,
            token: authenticator.accessToken,
          )..addAll(extraHeaders ?? const {});
          response = await sendForSession(headers);
        } else if (replay == UnauthorizedReplay.surfaceOriginal) {
          AppLogger.debug(
            'session refresh failed; surfacing the 401 from $method'
            ' ${uri.path}',
          );
        }
      }
    }
    if (!followRedirects &&
        response.statusCode >= 300 &&
        response.statusCode < 400) {
      // Never treat a redirect body as successful private data, never follow
      // it, and never forward this request or its Authorization header to the
      // new target. For a write, the outcome is explicitly unknown: the server
      // may have committed the change before answering with a redirect.
      throw NowaveApiException(
        statusCode: response.statusCode,
        code: 'HTTP_REDIRECT',
        message: 'Unexpected redirect from $method ${uri.path}.',
      );
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
      'user-agent': 'no-wave-app/1.0',
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
    bool followRedirects = true,
  }) async {
    final budget = timeout ?? this.timeout;
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..followRedirects = followRedirects;
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

  /// Unwraps `{data: ...}` and turns every failure into a typed exception.
  ///
  /// The mapping itself lives in [decodeEnvelope]; this method only logs the
  /// fixed diagnostic token for an unreadable body (issue #49) before
  /// rethrowing, so callers keep seeing one exception type for every failure.
  EnvelopeData _decode(String method, Uri uri, http.Response response) {
    final outcome = decodeEnvelope(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      retryAfterHeader: response.headers['retry-after'],
      requestLabel: '$method ${uri.path}',
      requestUri: '$method $uri',
    );
    switch (outcome) {
      case EnvelopeData():
        return outcome;
      case EnvelopeFailure(error: final error, fault: final fault):
        if (fault != null) {
          AppLogger.responseMalformed(
            method,
            uri.path,
            response.statusCode,
            fault.diagnostic,
          );
        }
        throw error;
    }
  }
}
