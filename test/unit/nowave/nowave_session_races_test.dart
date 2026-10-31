import 'dart:async';
import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store implements NowaveSessionStore {
  NowaveSessionData? value;
  Completer<void>? firstWriteGate;
  final Completer<void> firstWriteStarted = Completer<void>();
  var writes = 0;

  @override
  Future<NowaveSessionData?> read() async => value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<void> write(NowaveSessionData session) async {
    writes++;
    if (writes == 1 && firstWriteGate != null) {
      firstWriteStarted.complete();
      await firstWriteGate!.future;
    }
    value = session;
  }
}

NowaveSessionData _session(String user, String token) => NowaveSessionData(
  userId: user,
  email: '$user@example.invalid',
  accessToken: token,
  refreshToken: 'refresh-$user',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

NowaveTokenPair _pair(String token) => NowaveTokenPair(
  accessToken: token,
  refreshToken: 'refresh-$token',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

Map<String, Object> _response(String token) => {
  'accessToken': token,
  'refreshToken': 'refresh-$token',
  'accessExpiresAt': '2031-01-01T00:00:00Z',
  'refreshExpiresAt': '2031-01-01T00:00:00Z',
};

void main() {
  for (final rejected in [false, true]) {
    test(
      'old account refresh (${rejected ? 'rejected' : 'successful'}) cannot replace or clear a new login',
      () async {
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final client = NowaveApiClient(
          baseUrl: Uri.parse('https://api.example.invalid'),
          httpClient: MockClient((request) {
            started.complete();
            return response.future;
          }),
        );
        final store = _Store()..value = _session('alice', 'alice-token');
        final manager = NowaveSessionManager(client: client, store: store);
        await manager.restore();
        final refresh = manager.refresh();
        await started.future;
        await manager.adoptSession(
          _pair('bob-token'),
          email: 'bob@example.invalid',
        );
        await manager.updateUserId('bob');
        response.complete(
          rejected
              ? http.Response(
                  jsonEncode({
                    'error': {'code': 'UNAUTHENTICATED', 'message': 'expired'},
                  }),
                  401,
                )
              : http.Response(
                  jsonEncode({'data': _response('alice-rotated')}),
                  200,
                ),
        );
        expect(await refresh, isFalse);
        expect(manager.currentSession?.userId, 'bob');
        expect(manager.accessToken, 'bob-token');
        expect(store.value?.userId, 'bob');
      },
    );
  }

  test(
    'session writes and clears are serialized across account switches',
    () async {
      final store = _Store()..firstWriteGate = Completer<void>();
      final manager = NowaveSessionManager(
        client: NowaveApiClient(
          baseUrl: Uri.parse('https://api.example.invalid'),
        ),
        store: store,
      );
      final first = manager.adoptSession(
        _pair('alice-token'),
        email: 'alice@example.invalid',
      );
      await store.firstWriteStarted.future;
      final clear = manager.clear();
      final second = manager.adoptSession(
        _pair('bob-token'),
        email: 'bob@example.invalid',
      );
      store.firstWriteGate!.complete();
      await Future.wait([first, clear, second]);
      expect(manager.accessToken, 'bob-token');
      expect(store.value?.accessToken, 'bob-token');
    },
  );

  test(
    'expired logout refreshes and revokes the captured account, not a later login',
    () async {
      final refreshStarted = Completer<void>();
      final refreshResponse = Completer<http.Response>();
      final headers = <String?>[];
      final api = NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((request) {
          if (request.url.path.endsWith('/auth/refresh')) {
            expect(
              (jsonDecode(request.body) as Map)['refreshToken'],
              'refresh-alice',
            );
            refreshStarted.complete();
            return refreshResponse.future;
          }
          headers.add(request.headers['authorization']);
          return Future.value(
            headers.length == 1
                ? http.Response(
                    jsonEncode({
                      'error': {
                        'code': 'UNAUTHENTICATED',
                        'message': 'expired',
                      },
                    }),
                    401,
                  )
                : http.Response(jsonEncode({'data': null}), 200),
          );
        }),
      );
      final store = _Store()..value = _session('alice', 'alice-token');
      final manager = NowaveSessionManager(client: api, store: store);
      await manager.restore();
      final remote = AuthRemoteDataSourceImpl(api, manager);
      final logout = remote.logout();
      await refreshStarted.future;
      await manager.adoptSession(
        _pair('bob-token'),
        email: 'bob@example.invalid',
      );
      await manager.updateUserId('bob');
      refreshResponse.complete(
        http.Response(jsonEncode({'data': _response('alice-rotated')}), 200),
      );
      await logout;
      expect(headers, ['Bearer alice-token', 'Bearer alice-rotated']);
      expect(manager.currentSession?.userId, 'bob');
    },
  );

  test(
    'logout fences local work first and revokes only the captured token',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      String? authorization;
      final api = NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((request) {
          authorization = request.headers['authorization'];
          started.complete();
          return response.future;
        }),
      );
      final store = _Store()..value = _session('alice', 'alice-token');
      final manager = NowaveSessionManager(client: api, store: store);
      await manager.restore();
      final remote = AuthRemoteDataSourceImpl(api, manager);
      final logout = remote.logout();
      expect(manager.currentSession, isNull);
      await started.future;
      await manager.adoptSession(
        _pair('bob-token'),
        email: 'bob@example.invalid',
      );
      await manager.updateUserId('bob');
      response.complete(http.Response(jsonEncode({'data': null}), 200));
      await logout;
      expect(authorization, 'Bearer alice-token');
      expect(manager.currentSession?.userId, 'bob');
      expect(store.value?.userId, 'bob');
    },
  );
}
