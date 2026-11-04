import 'dart:async';
import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockReadingHistory extends Mock implements ReadingHistoryStore {}

class _AlwaysConnected implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => true;
}

class _NoopProfileCache implements ProfileCacheStore {
  @override
  Future<void> clear({required String userId}) async {}

  @override
  Future<CachedProfile?> read({required String userId}) async => null;

  @override
  Future<void> write({
    required String userId,
    required CachedProfile profile,
  }) async {}
}

http.Response _json(Object data, [int status = 200]) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _tokens(String id) => _json({
  'accessToken': 'access-$id',
  'refreshToken': 'refresh-$id',
  'accessExpiresAt': '2035-01-01T00:00:00.000Z',
  'refreshExpiresAt': '2035-01-01T00:00:00.000Z',
});

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
    if (failWrites) throw StateError('secure storage unavailable');
    stored = session;
  }
}

void main() {
  late _MemoryStore store;
  late NowaveSessionManager manager;
  late NowaveApiClient client;
  late List<String> requests;
  late AuthRemoteDataSourceImpl source;

  /// Builds the wiring. [loginReply] answers `/auth/login`, [handler] answers
  /// every other path.
  void build({
    http.Response Function(String account)? loginReply,
    required Future<http.Response> Function(http.Request request) handler,
    _MemoryStore? sessionStore,
  }) {
    store = sessionStore ?? _MemoryStore();
    requests = <String>[];
    manager = NowaveSessionManager(
      client: NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((_) async => _tokens('refresh')),
      ),
      store: store,
      now: () => DateTime.utc(2026),
    );
    client = NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: manager,
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/v1/auth/login' ||
            request.url.path == '/api/v1/auth/register') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final account = (body['email'] as String).split('@').first;
          return loginReply?.call(account) ?? _tokens(account);
        }
        return handler(request);
      }),
    );
    source = AuthRemoteDataSourceImpl(client, manager);
  }

  Future<http.Response> identity(http.Request request) async {
    if (request.url.path == '/api/v1/me') {
      return _json({'id': 'user-a'});
    }
    if (request.url.path == '/api/v1/me/profile') {
      return _json({
        'userId': 'user-a',
        'displayName': '作者 a',
        'updatedAt': '2025-01-01T00:00:00.000Z',
      });
    }
    return _json(<String, dynamic>{});
  }

  test('a failed identity lookup leaves no session behind', () async {
    build(
      handler: (request) async {
        // Both endpoints are down: the id cannot be recovered from either.
        if (request.url.path.startsWith('/api/v1/me')) {
          return _json({'error': 'boom'}, 500);
        }
        return identity(request);
      },
    );

    await expectLater(
      source.loginWithEmailPassword(
        email: 'a@example.invalid',
        password: 'secret',
      ),
      throwsA(isA<NowaveApiException>()),
    );

    // Memory, disk and the UI agree: this sign-in did not happen.
    expect(manager.currentSession, isNull);
    expect(store.stored, isNull);
    expect(requests, contains('DELETE /api/v1/me/session'));
  });

  test('a failed /me falls back to the profile id', () async {
    build(
      handler: (request) async {
        if (request.url.path == '/api/v1/me') {
          return _json({'error': 'boom'}, 500);
        }
        return identity(request);
      },
    );

    final user = await source.loginWithEmailPassword(
      email: 'a@example.invalid',
      password: 'secret',
    );

    // The profile answered, so this sign-in did happen - and the identity it
    // recorded is the one a restart restores.
    expect(user.id, 'user-a');
    expect(manager.currentSession?.userId, 'user-a');
    expect(store.stored?.userId, 'user-a');
    expect(requests, isNot(contains('DELETE /api/v1/me/session')));
  });

  test('a failed profile lookup leaves no session behind', () async {
    build(
      handler: (request) async {
        if (request.url.path == '/api/v1/me/profile') {
          return _json({'error': 'boom'}, 500);
        }
        return identity(request);
      },
    );

    await expectLater(
      source.loginWithEmailPassword(
        email: 'a@example.invalid',
        password: 'secret',
      ),
      throwsA(isA<NowaveApiException>()),
    );

    expect(manager.currentSession, isNull);
    expect(store.stored, isNull);
    expect(requests, contains('DELETE /api/v1/me/session'));
  });

  test('a session that cannot be stored is not reported as success', () async {
    build(handler: identity, sessionStore: _MemoryStore(failWrites: true));

    await expectLater(
      source.loginWithEmailPassword(
        email: 'a@example.invalid',
        password: 'secret',
      ),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionNotPersisted',
        ),
      ),
    );

    expect(store.writes, greaterThan(0));
    expect(store.stored, isNull);
    expect(manager.currentSession, isNull);
  });

  test('an unusable token pair is rejected before it is adopted', () async {
    build(
      loginReply: (_) => _json({
        'accessToken': '',
        'refreshToken': '',
        'accessExpiresAt': 'not-a-date',
        'refreshExpiresAt': 'not-a-date',
      }),
      handler: identity,
    );

    await expectLater(
      source.loginWithEmailPassword(
        email: 'a@example.invalid',
        password: 'secret',
      ),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.parse.invalidTokens',
        ),
      ),
    );

    expect(manager.currentSession, isNull);
    expect(store.writes, 0);
    expect(requests, isNot(contains('GET /api/v1/me')));
  });

  test('a late failure never clears a newer session', () async {
    final blocked = Completer<void>();
    final releaseIdentity = Completer<void>();
    build(
      handler: (request) async {
        if (request.url.path == '/api/v1/me' && !blocked.isCompleted) {
          blocked.complete();
          await releaseIdentity.future;
          return _json({'error': 'boom'}, 500);
        }
        return identity(request);
      },
    );

    // No intents here: the generation fence alone must protect the newer
    // session of an attempt whose older request fails afterwards.
    final slow = source.loginWithEmailPassword(
      email: 'a@example.invalid',
      password: 'secret',
    );
    await blocked.future;

    await source.loginWithEmailPassword(
      email: 'b@example.invalid',
      password: 'secret',
    );
    expect(manager.currentSession?.email, 'b@example.invalid');

    releaseIdentity.complete();
    await expectLater(slow, throwsA(isA<NowaveApiException>()));

    expect(manager.currentSession?.email, 'b@example.invalid');
    expect(store.stored?.email, 'b@example.invalid');
  });

  test('a sign-up that cannot load its profile is reported clearly', () async {
    build(
      handler: (request) async {
        if (request.url.path == '/api/v1/me') {
          return _json({'id': 'user-a'});
        }
        if (request.method == 'PUT') {
          return _json({'displayName': '作者 a'});
        }
        // The final profile read after the name was written.
        return _json({'error': 'boom'}, 500);
      },
    );

    await expectLater(
      source.signUpWithEmailPassword(
        name: '作者 a',
        email: 'a@example.invalid',
        password: 'secret',
      ),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.signedUpButSignedOut',
        ),
      ),
    );

    expect(manager.currentSession, isNull);
    expect(store.stored, isNull);
  });

  test('a successful sign-in stores one session in memory and disk', () async {
    build(handler: identity);

    final user = await source.loginWithEmailPassword(
      email: 'a@example.invalid',
      password: 'secret',
    );

    expect(user.id, 'user-a');
    expect(manager.currentSession?.userId, 'user-a');
    expect(store.stored?.userId, 'user-a');
    expect(store.stored?.accessToken, manager.currentSession?.accessToken);
    expect(requests, isNot(contains('DELETE /api/v1/me/session')));
  });

  test('the repository failure and the session store agree', () async {
    build(
      handler: (request) async {
        if (request.url.path.startsWith('/api/v1/me')) {
          return _json({'error': 'boom'}, 500);
        }
        return identity(request);
      },
    );
    final repository = AuthRepositoryImpl(
      source,
      _AlwaysConnected(),
      _NoopProfileCache(),
      readingHistoryStore: _MockReadingHistory(),
    );

    final result = await repository.loginWithEmailPassword(
      email: 'a@example.invalid',
      password: 'secret',
    );

    // What the UI is told (a failure) and what a restart would restore (no
    // session) cannot disagree.
    expect(result.getLeft().toNullable()?.kind, isNotNull);
    expect(manager.currentSession, isNull);
    expect(store.stored, isNull);
  });
}
