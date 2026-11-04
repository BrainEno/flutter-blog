import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/nowave/transport/api_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// The backend contract in one mapping: `{data: ...}` on success,
/// `{error: ...}` on failure, and a typed failure - never a null payload -
/// for anything else.
void main() {
  EnvelopeOutcome decode({
    int statusCode = 200,
    String body = '',
    Map<String, String> headers = const {},
  }) {
    return decodeEnvelope(
      statusCode: statusCode,
      bodyBytes: utf8.encode(body),
      retryAfterHeader: headers['retry-after'],
      requestLabel: 'GET /api/v1/articles',
      requestUri: 'GET https://api.example.com/api/v1/articles',
    );
  }

  EnvelopeFailure decodeFailure({
    int statusCode = 200,
    String body = '',
    Map<String, String> headers = const {},
  }) {
    final outcome = decode(
      statusCode: statusCode,
      body: body,
      headers: headers,
    );
    return outcome as EnvelopeFailure;
  }

  test('unwraps the data envelope', () {
    final outcome = decode(body: '{"data": {"id": "1", "title": "hi"}}');

    expect(outcome, isA<EnvelopeData>());
    expect((outcome as EnvelopeData).data, {'id': '1', 'title': 'hi'});
  });

  test('passes a non-object success body through', () {
    expect((decode(body: '[1, 2]') as EnvelopeData).data, [1, 2]);

    final nullData = decode(body: '{"data": null}') as EnvelopeData;
    expect(nullData.data, isNull);

    final empty = decode() as EnvelopeData;
    expect(empty.data, isNull, reason: 'an empty body carries no payload');
  });

  test('an error envelope keeps code, message and Retry-After', () {
    final failure = decodeFailure(
      statusCode: 429,
      body: '{"error": {"code": "RATE_LIMITED", "message": "slow down"}}',
      headers: {'retry-after': '7'},
    );

    expect(failure.fault, isNull);
    expect(failure.error.statusCode, 429);
    expect(failure.error.code, 'RATE_LIMITED');
    expect(failure.error.message, 'slow down');
    expect(failure.error.retryAfterSeconds, 7);
  });

  test('an error envelope with no fields falls back to safe defaults', () {
    final failure = decodeFailure(statusCode: 400, body: '{"error": {}}');

    expect(failure.error.code, 'UNKNOWN');
    expect(failure.error.message, 'The request failed.');
    expect(failure.error.retryAfterSeconds, isNull);
  });

  test('a 5xx body without the error envelope still fails typed', () {
    final failure = decodeFailure(statusCode: 503, body: '{"data": null}');

    expect(failure.fault, isNull);
    expect(failure.error.statusCode, 503);
    expect(failure.error.code, 'HTTP_503');
  });

  test('a non-JSON body is reported with its diagnostic token', () {
    final failure = decodeFailure(body: 'not json');

    expect(failure.fault, EnvelopeFault.nonJson);
    expect(failure.fault!.diagnostic, 'non-json');
    expect(failure.error.code, 'HTTP_200');
  });

  test('a non-UTF-8 body is reported with its diagnostic token', () {
    final outcome = decodeEnvelope(
      statusCode: 200,
      bodyBytes: Uint8List.fromList([0xff, 0xfe]),
      retryAfterHeader: null,
      requestLabel: 'GET /api/v1/articles',
      requestUri: 'GET https://api.example.com/api/v1/articles',
    );
    final failure = outcome as EnvelopeFailure;

    expect(failure.fault, EnvelopeFault.nonUtf8);
    expect(failure.fault!.diagnostic, 'non-utf8');
    expect(failure.error.code, 'HTTP_200');
  });

  test('an empty error body still fails instead of returning null data', () {
    final failure = decodeFailure(statusCode: 500);

    expect(failure.fault, isNull);
    expect(failure.error.code, 'HTTP_500');
  });

  test('requires an object payload where one is expected', () {
    expect(requireJsonMap({'id': '1'}, 'media asset'), {'id': '1'});

    expect(() => requireJsonMap([1], 'media asset'), throwsFormatException);
  });
}
