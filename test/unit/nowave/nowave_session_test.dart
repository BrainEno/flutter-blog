import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySessionStore implements NowaveSessionStore {
  NowaveSessionData? stored;

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async {
    stored = session;
  }

  @override
  Future<void> clear() async {
    stored = null;
  }
}

NowaveSessionData _session({
  String refreshToken = 'refresh-1',
  String userId = 'u1',
}) => NowaveSessionData(
  userId: userId,
  email: 'user@example.invalid',
  accessToken: 'access-1',
  refreshToken: refreshToken,
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

NowaveTokenPair _tokens(String n) => NowaveTokenPair(
  accessToken: 'access-$n',
  refreshToken: 'refresh-$n',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

Map<String, dynamic> _tokenBody(String n) => <String, dynamic>{
  'accessToken': 'access-$n',
  'tokenType': 'Bearer',
  'accessExpiresAt': '2031-01-01T00:00:00.000Z',
  'refreshToken': 'refresh-$n',
  'refreshExpiresAt': '2031-01-01T00:00:00.000Z',
};

void main() {
  group('restore', () {
    test('a persisted session is loaded into memory', () async {
      final store = MemorySessionStore()..stored = _session();
      final manager = NowaveSessionManager(client: clientFor(), store: store);

      await manager.restore();

      expect(manager.currentSession?.userId, 'u1');
      expect(manager.accessToken, 'access-1');
    });

    test('a corrupt persisted session is dropped, not thrown', () async {
      final manager = NowaveSessionManager(
        client: clientFor(),
        store: _ThrowingStore(),
      );

      await manager.restore();

      expect(manager.currentSession, isNull);
    });
  });

  group('adoptSession / updateUserId', () {
    test('the token pair and identity are persisted', () async {
      final store = MemorySessionStore();
      final manager = NowaveSessionManager(client: clientFor(), store: store);

      await manager.adoptSession(_tokens('2'), email: 'a@b.c');
      await manager.updateUserId('u9');

      expect(manager.accessToken, 'access-2');
      expect(store.stored?.userId, 'u9');
      expect(store.stored?.email, 'a@b.c');
      expect(store.stored?.refreshToken, 'refresh-2');
    });
  });

  group('refresh', () {
    test('a successful rotation replaces the pair and persists it', () async {
      final store = MemorySessionStore()..stored = _session();
      final manager = NowaveSessionManager(
        client: clientFor(body: _tokenBody('2')),
        store: store,
      );
      await manager.restore();

      final ok = await manager.refresh();

      expect(ok, isTrue);
      expect(manager.accessToken, 'access-2');
      expect(manager.currentSession?.refreshToken, 'refresh-2');
      expect(store.stored?.refreshToken, 'refresh-2');
      // The identity is preserved across the rotation.
      expect(manager.currentSession?.userId, 'u1');
    });

    test('concurrent refreshes share ONE request (single flight)', () async {
      int refreshRequests = 0;
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshRequests++;
            // Keep the request in flight long enough to overlap.
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response(jsonEncode({'data': _tokenBody('2')}), 200);
          }
          return http.Response(jsonEncode({'data': null}), 200);
        }),
      );
      final store = MemorySessionStore()..stored = _session();
      final manager = NowaveSessionManager(client: client, store: store);
      await manager.restore();

      final results = await Future.wait([
        manager.refresh(),
        manager.refresh(),
        manager.refresh(),
      ]);

      expect(results, everyElement(isTrue));
      expect(
        refreshRequests,
        1,
        reason:
            'a second concurrent refresh would reuse the rotated '
            'token and revoke the whole session family',
      );
    });

    test('a second refresh after the first completes rotates again', () async {
      int refreshRequests = 0;
      String current = '1';
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshRequests++;
            current = '${current}x';
            return http.Response(
              jsonEncode({'data': _tokenBody(current)}),
              200,
            );
          }
          return http.Response(jsonEncode({'data': null}), 200);
        }),
      );
      final store = MemorySessionStore()..stored = _session();
      final manager = NowaveSessionManager(client: client, store: store);
      await manager.restore();

      expect(await manager.refresh(), isTrue);
      expect(await manager.refresh(), isTrue);

      expect(
        refreshRequests,
        2,
        reason:
            'the single-flight slot must be released when a rotation '
            'completes, or later expiries reuse a stale future',
      );
      expect(manager.accessToken, 'access-1xx');
    });

    test(
      'a rejected rotation clears the session and broadcasts sign-out',
      () async {
        final store = MemorySessionStore()..stored = _session();
        final manager = NowaveSessionManager(
          client: clientFor(status: 401, error: 'UNAUTHENTICATED'),
          store: store,
        );
        await manager.restore();
        final statuses = <NowaveAuthStatus>[];
        final sub = manager.statusStream.listen(statuses.add);

        final ok = await manager.refresh();
        // The broadcast controller delivers asynchronously; let the event
        // land before asserting on it.
        await Future<void>.delayed(Duration.zero);

        expect(ok, isFalse);
        expect(manager.currentSession, isNull);
        expect(store.stored, isNull);
        expect(statuses, [isA<NowaveAuthSignedOut>()]);
        await sub.cancel();
      },
    );

    test(
      'refreshing without a session reports failure without network',
      () async {
        final manager = NowaveSessionManager(
          client: clientFor(),
          store: MemorySessionStore(),
        );

        expect(await manager.refresh(), isFalse);
      },
    );
  });

  group('clear', () {
    test('drops the local session and broadcasts sign-out once', () async {
      final store = MemorySessionStore()..stored = _session();
      final manager = NowaveSessionManager(client: clientFor(), store: store);
      await manager.restore();
      final statuses = <NowaveAuthStatus>[];
      final sub = manager.statusStream.listen(statuses.add);

      await manager.clear();
      await manager.clear();

      expect(statuses, hasLength(1));
      expect(store.stored, isNull);
      await sub.cancel();
    });
  });

  group('notifySignedIn', () {
    test('broadcasts the current user id', () async {
      final store = MemorySessionStore()..stored = _session();
      final manager = NowaveSessionManager(client: clientFor(), store: store);
      await manager.restore();
      final statuses = <NowaveAuthStatus>[];
      final sub = manager.statusStream.listen(statuses.add);

      manager.notifySignedIn();
      // The broadcast controller delivers asynchronously; let the event
      // land before asserting on it.
      await Future<void>.delayed(Duration.zero);

      expect(
        statuses.single,
        isA<NowaveAuthSignedIn>().having((s) => s.userId, 'userId', 'u1'),
      );
      await sub.cancel();
    });
  });
}

class _ThrowingStore implements NowaveSessionStore {
  @override
  Future<NowaveSessionData?> read() async => throw StateError('corrupt');

  @override
  Future<void> write(NowaveSessionData session) async {}

  @override
  Future<void> clear() async {}
}

/// Convenience client builder with a canned /auth/refresh answer.
NowaveApiClient clientFor({
  Map<String, dynamic> body = const {},
  int status = 200,
  String error = 'UNKNOWN',
}) {
  return NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    httpClient: MockClient((request) async {
      if (status >= 400) {
        return http.Response(
          jsonEncode({
            'error': {'code': error, 'message': 'rejected'},
          }),
          status,
        );
      }
      return http.Response(jsonEncode({'data': body}), status);
    }),
  );
  group('copyWith', () {
    test('replaces only the given fields', () {
      final session = _session();
      final rotated = session.copyWith(
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
      );

      expect(rotated.accessToken, 'access-2');
      expect(rotated.refreshToken, 'refresh-2');
      expect(rotated.userId, session.userId);
      expect(rotated.email, session.email);
      expect(rotated.accessExpiresAt, session.accessExpiresAt);
      expect(rotated.refreshExpiresAt, session.refreshExpiresAt);
    });
  });
}
