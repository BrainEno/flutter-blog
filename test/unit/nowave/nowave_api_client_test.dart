import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Scriptable authenticator: hands out a fixed token and counts refreshes.
class FakeAuthenticator implements NowaveAuthenticator {
  FakeAuthenticator([this._token = 'token-1']);

  String? _token;
  int refreshCalls = 0;

  @override
  String? get accessToken => _token;

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    _token = 'token-${refreshCalls + 1}';
    return true;
  }
}

NowaveApiClient clientFor(
  http.BaseClient inner, {
  NowaveAuthenticator? authenticator,
}) {
  return NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: authenticator,
    httpClient: inner,
  );
}

void main() {
  group('envelope handling', () {
    test('GET unwraps the data envelope', () async {
      final client = clientFor(
        MockClient((request) async {
          expect(request.url.toString(),
              'https://api.example.invalid/api/v1/articles?limit=10');
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'a'},
              ],
            }),
            200,
          );
        }),
      );

      final data = await client.getJson(
        '/articles',
        query: {'limit': '10'},
      );
      expect(data, isA<List>());
    });

    test('error envelopes throw NowaveApiException with the server code',
        () async {
      final client = clientFor(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'error': {'code': 'BAD_USER_INPUT', 'message': 'title must be a string.'},
            }),
            400,
          ),
        ),
      );

      await expectLater(
        client.postJson('/articles', {'title': ''}),
        throwsA(
          isA<NowaveApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.code, 'code', 'BAD_USER_INPUT'),
        ),
      );
    });

    test('non-JSON error responses still throw a typed exception', () async {
      final client = clientFor(
        MockClient((request) async => http.Response('<html>', 502)),
      );

      await expectLater(
        client.getJson('/articles'),
        throwsA(isA<NowaveApiException>()),
      );
    });
  });

  group('authentication', () {
    test('the bearer token is attached and JSON bodies carry a content type',
        () async {
      final authenticator = FakeAuthenticator();
      String? authHeader;
      String? contentType;
      final client = clientFor(
        MockClient((request) async {
          authHeader = request.headers['authorization'];
          contentType = request.headers['content-type'];
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
        authenticator: authenticator,
      );

      await client.postJson('/articles', {'title': 'x'});

      expect(authHeader, 'Bearer token-1');
      expect(contentType, 'application/json');
    });

    test('a 401 refreshes once and retries the request', () async {
      final authenticator = FakeAuthenticator('expired');
      final seenTokens = <String?>[];
      var calls = 0;
      final client = clientFor(
        MockClient((request) async {
          calls++;
          seenTokens.add(request.headers['authorization']);
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'error': {'code': 'UNAUTHENTICATED', 'message': 'expired'},
              }),
              401,
            );
          }
          return http.Response(jsonEncode({'data': {'ok': true}}), 200);
        }),
        authenticator: authenticator,
      );

      final data = await client.getJson('/me/profile');

      expect(calls, 2);
      expect(seenTokens, ['Bearer expired', 'Bearer token-2']);
      expect(authenticator.refreshCalls, 1);
      expect((data as Map)['ok'], isTrue);
    });

    test('a failed refresh does not retry: the 401 surfaces', () async {
      final authenticator = NowaveAuthenticatorDelegate(
        token: 'expired',
        refreshResult: false,
      );
      var calls = 0;
      final client = clientFor(
        MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'UNAUTHENTICATED', 'message': 'revoked'},
            }),
            401,
          );
        }),
        authenticator: authenticator,
      );

      await expectLater(
        client.getJson('/me/profile'),
        throwsA(
          isA<NowaveApiException>().having((e) => e.code, 'code',
              'UNAUTHENTICATED'),
        ),
      );
      expect(calls, 1);
    });

    test('unauthenticated calls send no bearer header', () async {
      String? authHeader;
      final client = clientFor(
        MockClient((request) async {
          authHeader = request.headers['authorization'];
          return http.Response(
            jsonEncode({
              'data': {'accessToken': 'a', 'refreshToken': 'r'},
            }),
            200,
          );
        }),
      );

      await client.postJson('/auth/login', {'email': 'a@b.c', 'password': 'p'},
          authenticate: false);

      expect(authHeader, isNull);
    });
  });

  group('media', () {
    test('uploads raw bytes with the picked content type and returns the '
        'asset', () async {
      final client = clientFor(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://api.example.invalid/api/v1/me/media',
          );
          expect(request.headers['content-type'], 'image/jpeg');
          expect(request.bodyBytes, [1, 2, 3]);
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'asset-1',
                'src': '/api/media/asset-1',
                'contentType': 'image/webp',
                'byteSize': 3,
                'width': 10,
                'height': 10,
              },
            }),
            201,
          );
        }),
      );

      final asset = await client.uploadMedia(
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );

      expect(asset.id, 'asset-1');
      expect(asset.contentType, 'image/webp');
      // The public URL is built from the verified /api/v1 route, not the
      // (v1-less) src field returned by the server.
      expect(
        client.mediaUri(asset.id).toString(),
        'https://api.example.invalid/api/v1/media/asset-1',
      );
    });
  });

  group('base URL handling', () {
    test('a base URL with a path prefix keeps the prefix', () async {
      Uri? seen;
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid/backend/'),
        httpClient: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'data': null}), 200);
        }),
      );

      await client.getJson('/articles');

      expect(seen.toString(),
          'https://example.invalid/backend/api/v1/articles');
    });
  });
}

/// Authenticator whose refresh result is scriptable.
class NowaveAuthenticatorDelegate implements NowaveAuthenticator {
  NowaveAuthenticatorDelegate({
    required String token,
    required this.refreshResult,
  }) : _token = token;

  final String _token;
  final bool refreshResult;

  @override
  String? get accessToken => _token;

  @override
  Future<bool> refresh() async => refreshResult;
}
