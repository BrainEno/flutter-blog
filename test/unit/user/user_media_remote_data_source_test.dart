import 'dart:async';
import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemorySessionStore implements NowaveSessionStore {
  NowaveSessionData? stored;

  @override
  Future<void> clear() async => stored = null;

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async => stored = session;
}

const _assetId = '64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01';

http.Response _json(Object data, {int statusCode = 200}) => http.Response(
  jsonEncode({'data': data}),
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _asset({String id = _assetId}) => {
  'id': id,
  'src': '/api/media/$id',
  'contentType': 'image/webp',
  'byteSize': 4096,
  'width': 1200,
  'height': 800,
  'createdAt': '2026-10-28T10:15:30.000Z',
  'orphan': true,
  'referencedBy': <String>[],
};

void main() {
  late NowaveSessionManager sessionManager;

  setUp(() {
    sessionManager = NowaveSessionManager(
      client: NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
      ),
      store: _MemorySessionStore(),
    );
  });

  Future<void> signInAs(String userId) async {
    final expiry = DateTime.utc(2035);
    await sessionManager.adoptSession(
      NowaveTokenPair(
        accessToken: 'access-$userId',
        refreshToken: 'refresh-$userId',
        accessExpiresAt: expiry,
        refreshExpiresAt: expiry,
      ),
      email: '$userId@example.invalid',
    );
    await sessionManager.updateUserId(userId);
  }

  UserRemoteDataSourceImpl sourceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: sessionManager,
      httpClient: MockClient(handler),
    );
    return UserRemoteDataSourceImpl(client, sessionManager);
  }

  test(
    'uses the authenticated media endpoint and builds canonical URLs',
    () async {
      await signInAs('user-a');
      final requests = <http.Request>[];
      final source = sourceFor((request) async {
        requests.add(request);
        return _json({
          'items': [_asset()],
          'nextCursor': 'opaque/next + cursor',
        });
      });
      final fence = NowaveSessionFence(
        userId: 'user-a',
        generation: sessionManager.sessionGeneration,
      );

      final page = await source.getMediaLibraryPage(sessionFence: fence);

      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/me/media');
      expect(request.url.queryParameters, {'limit': '24'});
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], 'Bearer access-user-a');
      expect(page.nextCursor, 'opaque/next + cursor');
      expect(page.items, hasLength(1));
      expect(
        page.items.single.imageUrl,
        'https://api.example.invalid/api/v1/media/$_assetId',
      );
      expect(page.items.single.width, 1200);
      expect(page.items.single.height, 800);
      expect(page.items.single.byteSize, 4096);
      expect(
        page.items.single.createdAt,
        DateTime.utc(2026, 10, 28, 10, 15, 30),
      );
    },
  );

  test(
    'passes an opaque cursor unchanged and rejects a stale fence before GET',
    () async {
      await signInAs('user-a');
      final requests = <http.Request>[];
      final source = sourceFor((request) async {
        requests.add(request);
        return _json({'items': <Object>[], 'nextCursor': null});
      });
      final fence = NowaveSessionFence(
        userId: 'user-a',
        generation: sessionManager.sessionGeneration,
      );

      await source.getMediaLibraryPage(
        sessionFence: fence,
        cursor: 'cursor/+?opaque==',
      );

      expect(
        requests.single.url.queryParameters['cursor'],
        'cursor/+?opaque==',
      );
      expect(requests.single.url.queryParameters['limit'], '24');

      final staleFence = NowaveSessionFence(
        userId: 'user-a',
        generation: fence.generation - 1,
      );
      await expectLater(
        source.getMediaLibraryPage(sessionFence: staleFence),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'code',
            'auth.sessionChanged',
          ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );

  test('drops a page if the account changes while it is in flight', () async {
    await signInAs('user-a');
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final source = sourceFor((request) async {
      requestStarted.complete();
      await releaseResponse.future;
      return _json({
        'items': [_asset()],
        'nextCursor': null,
      });
    });
    final fence = NowaveSessionFence(
      userId: 'user-a',
      generation: sessionManager.sessionGeneration,
    );

    final pending = source.getMediaLibraryPage(sessionFence: fence);
    await requestStarted.future;
    await signInAs('user-b');
    releaseResponse.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionChanged',
        ),
      ),
    );
  });

  test('rejects malformed media metadata instead of trusting it', () async {
    await signInAs('user-a');
    final malformed = _asset()..['width'] = 0;
    final source = sourceFor(
      (_) async => _json({
        'items': [malformed],
        'nextCursor': null,
      }),
    );
    final fence = NowaveSessionFence(
      userId: 'user-a',
      generation: sessionManager.sessionGeneration,
    );

    await expectLater(
      source.getMediaLibraryPage(sessionFence: fence),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'client.parse',
        ),
      ),
    );
  });

  test('maps a missing media endpoint to a stable feature failure', () async {
    await signInAs('user-a');
    final source = sourceFor(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'NOT_FOUND', 'message': 'no route'},
        }),
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final fence = NowaveSessionFence(
      userId: 'user-a',
      generation: sessionManager.sessionGeneration,
    );

    await expectLater(
      source.getMediaLibraryPage(sessionFence: fence),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'user.mediaLibraryUnavailable',
        ),
      ),
    );
  });
}
