import 'dart:async';
import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

NowaveTokenPair _tokens(String id) => NowaveTokenPair(
  accessToken: 'access-$id',
  refreshToken: 'refresh-$id',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2035),
);

NowaveSessionData _session(String id) => NowaveSessionData(
  userId: 'user-$id',
  email: '$id@example.invalid',
  accessToken: 'access-$id',
  refreshToken: 'refresh-$id',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2035),
);

http.Response _rotated(String id) => http.Response(
  jsonEncode({
    'data': {
      'accessToken': 'access-$id',
      'refreshToken': 'refresh-$id',
      'accessExpiresAt': '2035-01-01T00:00:00.000Z',
      'refreshExpiresAt': '2035-01-01T00:00:00.000Z',
    },
  }),
  200,
);

NowaveApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient(handler),
    );

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

class _BlockingStore extends _MemoryStore {
  _BlockingStore({this.blockRead = false, this.blockFirstWrite = false});

  final bool blockRead;
  final bool blockFirstWrite;
  final started = Completer<void>();
  final release = Completer<void>();
  int writes = 0;

  @override
  Future<NowaveSessionData?> read() async {
    final snapshot = stored;
    if (blockRead) {
      started.complete();
      await release.future;
    }
    return snapshot;
  }

  @override
  Future<void> write(NowaveSessionData session) async {
    writes++;
    if (blockFirstWrite && writes == 1) {
      started.complete();
      await release.future;
    }
    stored = session;
  }
}

void main() {
  test('a delayed logout cannot clear a newly adopted account', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final store = _MemoryStore(_session('A'));
    final manager = NowaveSessionManager(
      client: _client((_) async => _rotated('unused')),
      store: store,
    );
    await manager.restore();
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: manager,
      httpClient: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final source = AuthRemoteDataSourceImpl(client, manager);
    final pending = source.logout();
    final expectation = expectLater(
      pending,
      throwsA(
        isA<NowaveApiException>().having(
          (error) => error.code,
          'code',
          'SESSION_CHANGED',
        ),
      ),
    );
    await started.future;
    await manager.adoptSession(_tokens('B'), email: 'b@example.invalid');
    response.complete(http.Response(jsonEncode({'data': null}), 200));
    await expectation;
    expect(manager.accessToken, 'access-B');
    expect(store.stored?.accessToken, 'access-B');
  });

  test(
    'a successful stale refresh cannot resurrect a signed-out session',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final store = _MemoryStore(_session('A'));
      final manager = NowaveSessionManager(
        client: _client((_) {
          started.complete();
          return response.future;
        }),
        store: store,
      );
      await manager.restore();
      final pending = manager.refresh();
      await started.future;
      await manager.clear();
      response.complete(_rotated('A2'));

      expect(await pending, isFalse);
      expect(manager.currentSession, isNull);
      expect(store.stored, isNull);
    },
  );

  test(
    'a stale refresh rejection cannot sign out a newly adopted account',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final store = _MemoryStore(_session('A'));
      final manager = NowaveSessionManager(
        client: _client((_) {
          started.complete();
          return response.future;
        }),
        store: store,
      );
      await manager.restore();
      final pending = manager.refresh();
      await started.future;
      await manager.adoptSession(_tokens('B'), email: 'b@example.invalid');
      response.complete(
        http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHENTICATED', 'message': 'revoked'},
          }),
          401,
        ),
      );

      expect(await pending, isFalse);
      expect(manager.accessToken, 'access-B');
      expect(store.stored?.accessToken, 'access-B');
    },
  );

  test(
    'new sessions have their own single-flight and retain identity updates',
    () async {
      final aStarted = Completer<void>();
      final bStarted = Completer<void>();
      final aResponse = Completer<http.Response>();
      final bResponse = Completer<http.Response>();
      var bRequests = 0;
      final store = _MemoryStore(_session('A'));
      final manager = NowaveSessionManager(
        client: _client((request) {
          final token = (jsonDecode(request.body) as Map)['refreshToken'];
          if (token == 'refresh-A') {
            aStarted.complete();
            return aResponse.future;
          }
          bRequests++;
          if (!bStarted.isCompleted) bStarted.complete();
          return bResponse.future;
        }),
        store: store,
      );
      await manager.restore();
      final oldRefresh = manager.refresh();
      await aStarted.future;
      await manager.adoptSession(_tokens('B'), email: 'b@example.invalid');
      final newRefresh = manager.refresh();
      await bStarted.future;
      await manager.updateUserId('user-B');
      aResponse.complete(_rotated('A2'));
      expect(await oldRefresh, isFalse);
      final anotherNewRefresh = manager.refresh();
      bResponse.complete(_rotated('B2'));

      expect(await Future.wait([newRefresh, anotherNewRefresh]), [true, true]);
      expect(bRequests, 1);
      expect(manager.currentSession?.userId, 'user-B');
      expect(manager.accessToken, 'access-B2');
      expect(store.stored?.userId, 'user-B');
    },
  );

  test(
    'persist, sign-out and replacement are serialized in intent order',
    () async {
      final store = _BlockingStore(blockFirstWrite: true);
      final manager = NowaveSessionManager(
        client: _client((_) async => _rotated('unused')),
        store: store,
      );
      final statuses = <NowaveAuthStatus>[];
      final subscription = manager.statusStream.listen(statuses.add);
      addTearDown(subscription.cancel);

      final writeA = manager.adoptSession(
        _tokens('A'),
        email: 'a@example.invalid',
      );
      await store.started.future;
      final signOut = manager.clear();
      final writeB = manager.adoptSession(
        _tokens('B'),
        email: 'b@example.invalid',
      );
      store.release.complete();
      await Future.wait([writeA, signOut, writeB]);
      await Future<void>.delayed(Duration.zero);

      expect(manager.accessToken, 'access-B');
      expect(store.stored?.accessToken, 'access-B');
      expect(statuses.whereType<NowaveAuthSignedOut>(), isEmpty);
    },
  );

  test('a delayed restore cannot overwrite a newer account', () async {
    final store = _BlockingStore(blockRead: true)..stored = _session('A');
    final manager = NowaveSessionManager(
      client: _client((_) async => _rotated('unused')),
      store: store,
    );
    final restore = manager.restore();
    await store.started.future;
    final adopt = manager.adoptSession(
      _tokens('B'),
      email: 'b@example.invalid',
    );
    store.release.complete();
    await Future.wait([restore, adopt]);
    expect(manager.accessToken, 'access-B');
    expect(store.stored?.accessToken, 'access-B');
  });
}
