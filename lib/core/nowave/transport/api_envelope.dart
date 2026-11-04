import 'dart:convert';

import 'package:belog/core/nowave/transport/api_error.dart';

/// Why a response body could not be read as the documented envelope.
///
/// The token is recorded in the diagnostics buffer (issue #49); it is a fixed
/// string, never part of the body.
enum EnvelopeFault {
  nonUtf8('non-utf8'),
  nonJson('non-json');

  const EnvelopeFault(this.diagnostic);

  final String diagnostic;
}

/// The decoded result of one HTTP response.
sealed class EnvelopeOutcome {
  const EnvelopeOutcome();
}

/// The unwrapped `data` payload (null when the endpoint sent none).
final class EnvelopeData extends EnvelopeOutcome {
  const EnvelopeData(this.data);

  final dynamic data;
}

/// The request failed: either the backend's `{error: ...}` body, or a body
/// that did not have the documented shape.
final class EnvelopeFailure extends EnvelopeOutcome {
  const EnvelopeFailure(this.error, {this.fault});

  final NowaveApiException error;

  /// Set when the body itself was unreadable, so the caller can log the
  /// fixed diagnostic token before rethrowing.
  final EnvelopeFault? fault;
}

/// Turns one response into a payload or a typed failure.
///
/// The mapping is the backend contract in one place: every `{error: ...}`
/// body becomes a [NowaveApiException] carrying the stable [code], every
/// `>= 400` response that does *not* look like the documented envelope still
/// fails (callers must never see a vague unparseable-payload error for a
/// server failure), and an unreadable body is reported as [EnvelopeFault].
///
/// [requestLabel] is `METHOD /path` (no query) and [requestUri] the full URI;
/// both only appear in the exception message, which stays in `cause`.
EnvelopeOutcome decodeEnvelope({
  required int statusCode,
  required List<int> bodyBytes,
  required String? retryAfterHeader,
  required String requestLabel,
  required String requestUri,
}) {
  final String rawBody;
  try {
    rawBody = utf8.decode(bodyBytes);
  } on FormatException {
    return EnvelopeFailure(
      NowaveApiException(
        statusCode: statusCode,
        code: 'HTTP_$statusCode',
        message: 'Unexpected non-UTF-8 response from $requestUri.',
      ),
      fault: EnvelopeFault.nonUtf8,
    );
  }

  final dynamic body;
  try {
    body = rawBody.isEmpty ? null : jsonDecode(rawBody);
  } on FormatException {
    return EnvelopeFailure(
      NowaveApiException(
        statusCode: statusCode,
        code: 'HTTP_$statusCode',
        message: 'Unexpected non-JSON response from $requestUri.',
      ),
      fault: EnvelopeFault.nonJson,
    );
  }

  if (body is Map<String, dynamic>) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      return EnvelopeFailure(
        NowaveApiException(
          statusCode: statusCode,
          code: error['code'] as String? ?? 'UNKNOWN',
          message: error['message'] as String? ?? 'The request failed.',
          retryAfterSeconds: int.tryParse(retryAfterHeader ?? ''),
        ),
      );
    }
    if (statusCode >= 400) {
      return EnvelopeFailure(
        NowaveApiException(
          statusCode: statusCode,
          code: 'HTTP_$statusCode',
          message:
              'Unexpected error response shape from $requestLabel: '
              '${body.keys.join(',')}',
        ),
      );
    }
    return EnvelopeData(body['data']);
  }
  if (statusCode >= 400) {
    return EnvelopeFailure(
      NowaveApiException(
        statusCode: statusCode,
        code: 'HTTP_$statusCode',
        message: 'Unexpected non-JSON error response from $requestLabel.',
      ),
    );
  }
  return EnvelopeData(body);
}

/// Requires an object payload for the endpoints that answer with one.
Map<String, dynamic> requireJsonMap(dynamic data, String what) {
  if (data is Map<String, dynamic>) return data;
  throw FormatException('Unexpected $what payload: $data');
}
