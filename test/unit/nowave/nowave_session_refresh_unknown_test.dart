import 'dart:convert';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A refresh token rotates once and replaying it revokes the whole session
/// family, so a rotation whose answer never arrived must never be retried
/// (#101).
class _MemoryStore implements NowaveSessionStore {
  _MemoryStore({this.failWrites = false});

  NowaveSessionData? stored;
  final bool failWrites;
  int writes = 0;

  @override
  Future<void> clear() async {
    stored = null;
  }

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async {
    writes++;
    if (failWrites) throw const FileSystemException('disk full');
    stored = session;
  }
}

final DateTime now = DateTime.utc(2026, 6, 1, 12);

NowaveSessionData _session({
  DateTime? accessExpiresAt,
  bool refreshTokenSpent = false,
}) => NowaveSessionData(
  userId: 'u1',
  email: 'user@example.invalid',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: accessExpiresAt ?? now.add(const Duration(hours: 1)),
  refreshExpiresAt: now.add(const Duration(days: 30)),
  refreshTokenSpent: refreshTokenSpent,
);

Map<String, dynamic> _tokenBody(String n) => <String, dynamic>{
  'accessToken': 'access-$n',
  'tokenType': 'Bearer',
  'accessExpiresAt': '2031-01-01T00:00:00.000Z',
  'refreshToken': 'refresh-$n',
  'refreshExpiresAt': '2031-01-01T00:00:00.000Z',
};

/// Builds a manager plus a request counter over [handler].
({NowaveSessionManager manager, int Function() calls}) _manager(
  _MemoryStore store, {
  required http.Response Function() handler,
  bool throws = false,
  Object? error,
}) {
  var calls = 0;
  final client = NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    httpClient: MockClient((request) async {
      calls++;
      if (throws) throw error ?? const SocketException('network unreachable');
      return handler();
    }),
  );
  final manager = NowaveSessionManager(
    client: client,
    store: store,
    now: () => now,
  );
  return (manager: manager, calls: () => calls);
}

void main() {
  test('an unknown rotation outcome retires the refresh token', () async {
    final store = _MemoryStore()..stored = _session();
    final built = _manager(
      store,
      handler: () => http.Response('', 500),
      throws: true,
    );
    await built.manager.restore();
    final statuses = <NowaveAuthStatus>[];
    final sub = built.manager.statusStream.listen(statuses.add);

    expect(await built.manager.refresh(), isFalse);

    // Kept: the access token may still work. Retired: the refresh token may
    // already have been rotated server-side.
    expect(built.manager.currentSession, isNotNull);
    expect(built.manager.currentSession!.refreshTokenSpent, isTrue);
    expect(store.stored?.refreshTokenSpent, isTrue);
    expect(statuses, isEmpty);

    // The next request for a rotation never resends it; it ends the session.
    expect(await built.manager.refresh(), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(built.calls(), 1);
    expect(built.manager.currentSession, isNull);
    expect(store.stored, isNull);
    expect(statuses, [isA<NowaveAuthSignedOut>()]);
    await sub.cancel();
  });

  test('a 5xx during the rotation is also an unknown outcome', () async {
    final store = _MemoryStore()..stored = _session();
    final built = _manager(
      store,
      handler: () => http.Response('{"error":"boom"}', 503),
      throws: false,
    );
    await built.manager.restore();

    expect(await built.manager.refresh(), isFalse);

    expect(built.manager.currentSession!.refreshTokenSpent, isTrue);
    expect(store.stored?.refreshTokenSpent, isTrue);
  });

  test('a rejection still drops the session at once', () async {
    final store = _MemoryStore()..stored = _session();
    final built = _manager(
      store,
      handler: () => http.Response(
        jsonEncode({
          'error': {'code': 'UNAUTHENTICATED'},
        }),
        401,
      ),
      throws: false,
    );
    await built.manager.restore();
    final statuses = <NowaveAuthStatus>[];
    final sub = built.manager.statusStream.listen(statuses.add);

    expect(await built.manager.refresh(), isFalse);
    await Future<void>.delayed(Duration.zero);

    // A definitive rejection is not "unknown": nothing is kept for reuse.
    expect(built.manager.currentSession, isNull);
    expect(store.stored, isNull);
    expect(statuses, [isA<NowaveAuthSignedOut>()]);
    await sub.cancel();
  });

  test('the retirement survives a restart', () async {
    final stored = NowaveSessionManager.decodeSession(
      NowaveSessionManager.encodeSession(
        _session(
          accessExpiresAt: now.subtract(const Duration(minutes: 1)),
          refreshTokenSpent: true,
        ),
      ),
    );
    final store = _MemoryStore()..stored = stored;
    final built = _manager(store, handler: () => http.Response('', 500));
    await built.manager.restore();

    expect(built.manager.currentSession!.refreshTokenSpent, isTrue);
    // Nothing to spend: the access token is gone, so the session ends here
    // instead of replaying the token the server may already have rotated.
    expect(await built.manager.ensureFreshAccess(), isFalse);

    expect(built.calls(), 0);
    expect(built.manager.currentSession, isNull);
    expect(store.stored, isNull);
  });

  test('a spent token keeps a still-valid access token alive', () async {
    final store = _MemoryStore()..stored = _session(refreshTokenSpent: true);
    final built = _manager(store, handler: () => http.Response('', 500));
    await built.manager.restore();

    // Inside the proactive window, but the access token has not expired yet:
    // use it rather than signing out early.
    expect(await built.manager.ensureFreshAccess(), isFalse);

    expect(built.calls(), 0);
    expect(built.manager.currentSession, isNotNull);
    expect(store.stored, isNotNull);
  });

  test('a rotation that cannot be persisted drops the stale copy', () async {
    final store = _MemoryStore(failWrites: true)..stored = _session();
    final built = _manager(
      store,
      handler: () => http.Response(
        jsonEncode({'data': _tokenBody('2')}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
      throws: false,
    );
    await built.manager.restore();

    expect(await built.manager.refresh(), isTrue);

    // The rotated pair only exists in memory; the store keeps no token that a
    // restart could replay.
    expect(built.manager.currentSession!.refreshToken, 'refresh-2');
    expect(store.stored, isNull);

    final restarted = _manager(store, handler: () => http.Response('', 500));
    await restarted.manager.restore();
    expect(restarted.manager.currentSession, isNull);
    expect(await restarted.manager.refresh(), isFalse);
    expect(restarted.calls(), 0);
  });
}
