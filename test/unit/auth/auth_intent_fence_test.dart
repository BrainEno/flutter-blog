import 'dart:async';
import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/domain/auth_intent_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _tokens(String id) => _json({
  'accessToken': 'access-$id',
  'refreshToken': 'refresh-$id',
  'accessExpiresAt': '2035-01-01T00:00:00.000Z',
  'refreshExpiresAt': '2035-01-01T00:00:00.000Z',
});

class _MemoryStore implements NowaveSessionStore {
  _MemoryStore([this.stored]);

  NowaveSessionData? stored;

  @override
  Future<void> clear() async {
    stored = null;
  }

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async {
    stored = session;
  }
}

void main() {
  late AuthIntentGate gate;
  late _MemoryStore store;
  late NowaveSessionManager manager;
  late AuthRemoteDataSourceImpl source;
  late String activeAccount;

  /// Rebuilds the wiring with [hold] returning a future that delays the
  /// `/auth/login` reply for the given account.
  void build({Future<void> Function(String account)? hold}) {
    gate = AuthIntentGate();
    store = _MemoryStore();
    activeAccount = '';
    manager = NowaveSessionManager(
      client: NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((_) async => _tokens('refresh')),
      ),
      store: store,
      now: () => DateTime.utc(2026),
    );
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: manager,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/auth/login') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final email = body['email'] as String;
          final account = email.split('@').first;
          final delay = hold?.call(account);
          if (delay != null) await delay;
          activeAccount = account;
          return _tokens(account);
        }
        if (path == '/api/v1/me') {
          return _json({'id': 'user-$activeAccount'});
        }
        if (path == '/api/v1/me/profile') {
          return _json({
            'userId': 'user-$activeAccount',
            'displayName': '作者 $activeAccount',
            'updatedAt': '2025-01-01T00:00:00.000Z',
          });
        }
        return http.Response('not found', 404);
      }),
    );
    source = AuthRemoteDataSourceImpl(client, manager, intentGate: gate);
  }

  test('a slow older sign-in cannot adopt after a newer one', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    build(
      hold: (account) {
        if (account != 'a') return null;
        if (!started.isCompleted) started.complete();
        return release.future;
      },
    );

    final firstIntent = gate.begin();
    final slow = source.loginWithEmailPassword(
      email: 'a@example.invalid',
      password: 'secret',
      intent: firstIntent,
    );
    await started.future;

    final secondIntent = gate.begin();
    final winner = await source.loginWithEmailPassword(
      email: 'b@example.invalid',
      password: 'secret',
      intent: secondIntent,
    );
    expect(winner.id, 'user-b');
    expect(manager.currentSession?.email, 'b@example.invalid');

    // The user's earlier attempt finally answers: its tokens must never
    // replace the account that was chosen afterwards.
    release.complete();
    await expectLater(
      slow,
      throwsA(
        isA<NowaveApiException>().having(
          (error) => error.code,
          'code',
          'SESSION_SUPERSEDED',
        ),
      ),
    );
    expect(manager.currentSession?.email, 'b@example.invalid');
    expect(store.stored?.email, 'b@example.invalid');
  });

  test('an intent that is already stale never adopts anything', () async {
    build();

    final stale = gate.begin();
    gate.begin();

    await expectLater(
      source.loginWithEmailPassword(
        email: 'a@example.invalid',
        password: 'secret',
        intent: stale,
      ),
      throwsA(isA<NowaveApiException>()),
    );
    expect(manager.currentSession, isNull);
    expect(store.stored, isNull);
  });

  test('the newest intent still signs in normally', () async {
    build();

    final intent = gate.begin();
    final user = await source.loginWithEmailPassword(
      email: 'b@example.invalid',
      password: 'secret',
      intent: intent,
    );

    expect(user.id, 'user-b');
    expect(user.name, '作者 b');
    expect(manager.currentSession?.userId, 'user-b');
    expect(store.stored?.userId, 'user-b');
  });

  test('a caller without an intent keeps the generation fence', () async {
    build();

    final user = await source.loginWithEmailPassword(
      email: 'b@example.invalid',
      password: 'secret',
    );

    expect(user.id, 'user-b');
    expect(manager.currentSession?.email, 'b@example.invalid');
  });
}
