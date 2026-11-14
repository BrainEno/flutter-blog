import 'dart:async';
import 'dart:convert';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/repositories/password_recovery_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _location = 'https://destination.example.invalid/private';
const _password = 'ExamplePass123!';
const _resetToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

class _Store implements NowaveSessionStore {
  NowaveSessionData? value;
  int writes = 0;
  int clears = 0;
  @override
  Future<NowaveSessionData?> read() async => value;
  @override
  Future<void> write(NowaveSessionData session) async {
    writes++;
    value = session;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class _Online implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => true;
}

NowaveSessionData _session() => NowaveSessionData(
  userId: 'author',
  email: 'author@example.invalid',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2035),
);

void main() {
  group('refresh token redirect outcome', () {
    for (final status in [302, 307]) {
      test(
        '$status retires ambiguous refresh token and does not resend',
        () async {
          final seen = <http.Request>[];
          final store = _Store()..value = _session();
          final transport = MockClient((request) async {
            seen.add(request);
            return http.Response(
              '{"data":{"accessToken":"fake"}}',
              status,
              headers: {'location': _location},
            );
          });
          addTearDown(transport.close);
          final manager = NowaveSessionManager(
            client: NowaveApiClient(
              baseUrl: Uri.parse('https://api.example.invalid'),
              httpClient: transport,
            ),
            store: store,
          );
          await manager.restore();
          final generation = manager.sessionGeneration;
          expect(await manager.refresh(), isFalse);
          expect(seen, hasLength(1));
          expect(seen.single.url.path, '/api/v1/auth/refresh');
          expect(seen.single.followRedirects, isFalse);
          expect(seen.single.headers['authorization'], isNull);
          expect(jsonDecode(seen.single.body), {'refreshToken': 'refresh'});
          expect(manager.currentSession?.refreshTokenSpent, isTrue);
          expect(store.value?.refreshTokenSpent, isTrue);
          expect(manager.sessionGeneration, generation);
          expect(await manager.refresh(), isFalse);
          expect(seen, hasLength(1));
          expect(manager.currentSession, isNull);
          expect(store.clears, 1);
        },
      );
    }

    test(
      'parallel refreshes share one redirect and one retired token',
      () async {
        final gate = Completer<http.Response>();
        final started = Completer<void>();
        var calls = 0;
        final store = _Store()..value = _session();
        final transport = MockClient((request) {
          calls++;
          started.complete();
          return gate.future;
        });
        addTearDown(transport.close);
        final manager = NowaveSessionManager(
          client: NowaveApiClient(
            baseUrl: Uri.parse('https://api.example.invalid'),
            httpClient: transport,
          ),
          store: store,
        );
        await manager.restore();
        final first = manager.refresh();
        final second = manager.refresh();
        await started.future;
        gate.complete(http.Response('', 307, headers: {'location': _location}));
        expect(await Future.wait([first, second]), [false, false]);
        expect(calls, 1);
        expect(store.value?.refreshTokenSpent, isTrue);
        expect(store.writes, 1);
      },
    );

    test(
      'an old redirected refresh cannot retire a replacement session',
      () async {
        final gate = Completer<http.Response>();
        final started = Completer<void>();
        final store = _Store()..value = _session();
        final transport = MockClient((_) {
          started.complete();
          return gate.future;
        });
        addTearDown(transport.close);
        final manager = NowaveSessionManager(
          client: NowaveApiClient(
            baseUrl: Uri.parse('https://api.example.invalid'),
            httpClient: transport,
          ),
          store: store,
        );
        await manager.restore();
        final oldRefresh = manager.refresh();
        await started.future;
        final replacement = NowaveTokenPair(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          accessExpiresAt: DateTime.utc(2035),
          refreshExpiresAt: DateTime.utc(2035),
        );
        await manager.adoptSession(replacement, email: 'other@example.invalid');
        await manager.updateUserId('other');
        gate.complete(http.Response('', 302, headers: {'location': _location}));
        expect(await oldRefresh, isFalse);
        expect(manager.currentSession?.userId, 'other');
        expect(manager.currentSession?.refreshToken, 'new-refresh');
        expect(manager.currentSession?.refreshTokenSpent, isFalse);
        expect(store.value?.userId, 'other');
        expect(store.value?.refreshTokenSpent, isFalse);
      },
    );
  });

  group('authentication and recovery redirects', () {
    for (final status in [302, 307]) {
      test('login $status cannot adopt a redirected fake session', () async {
        final store = _Store();
        final requests = <http.Request>[];
        final transport = MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'data': {
                'accessToken': 'fake',
                'refreshToken': 'fake',
                'accessExpiresAt': '2035-01-01T00:00:00Z',
                'refreshExpiresAt': '2035-01-01T00:00:00Z',
              },
            }),
            status,
            headers: {'location': _location},
          );
        });
        addTearDown(transport.close);
        final client = NowaveApiClient(
          baseUrl: Uri.parse('https://api.example.invalid'),
          httpClient: transport,
        );
        final manager = NowaveSessionManager(client: client, store: store);
        await manager.restore();
        final dataSource = AuthRemoteDataSourceImpl(client, manager);
        await expectLater(
          dataSource.loginWithEmailPassword(
            email: 'a@example.invalid',
            password: _password,
          ),
          throwsA(
            isA<NowaveApiException>().having(
              (error) => error.code,
              'code',
              'HTTP_REDIRECT',
            ),
          ),
        );
        expect(requests, hasLength(1));
        expect(requests.single.url.path, '/api/v1/auth/login');
        expect(requests.single.followRedirects, isFalse);
        expect(manager.currentSession, isNull);
        expect(store.value, isNull);
        expect(store.writes, 0);
      });

      test('registration $status cannot create a local session', () async {
        final store = _Store();
        final transport = MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            '{"data":{"accessToken":"fake"}}',
            status,
            headers: {'location': _location},
          );
        });
        addTearDown(transport.close);
        final client = NowaveApiClient(
          baseUrl: Uri.parse('https://api.example.invalid'),
          httpClient: transport,
        );
        final manager = NowaveSessionManager(client: client, store: store);
        await manager.restore();
        final dataSource = AuthRemoteDataSourceImpl(client, manager);
        await expectLater(
          dataSource.signUpWithEmailPassword(
            name: 'Author',
            email: 'a@example.invalid',
            password: _password,
          ),
          throwsA(
            isA<NowaveApiException>().having(
              (error) => error.code,
              'code',
              'HTTP_REDIRECT',
            ),
          ),
        );
        expect(manager.currentSession, isNull);
        expect(store.writes, 0);
      });

      test(
        'forgot password $status reports unknown outcome without retry',
        () async {
          final requests = <http.Request>[];
          final transport = MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{"data":{"ok":true}}',
              status,
              headers: {'location': _location},
            );
          });
          addTearDown(transport.close);
          final repository = PasswordRecoveryRepositoryImpl(
            client: NowaveApiClient(
              baseUrl: Uri.parse('https://api.example.invalid'),
              httpClient: transport,
            ),
            connectionChecker: _Online(),
          );
          final result = await repository.requestPasswordReset(
            email: 'a@example.invalid',
          );
          expect(
            result.getLeft().toNullable()?.code,
            'auth.passwordRecoveryRequestOutcomeUnknown',
          );
          expect(requests, hasLength(1));
          expect(requests.single.followRedirects, isFalse);
          expect(requests.single.headers['authorization'], isNull);
        },
      );

      test(
        'password reset $status reports unknown outcome without retry',
        () async {
          final requests = <http.Request>[];
          final transport = MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{"data":{"ok":true}}',
              status,
              headers: {'location': _location},
            );
          });
          addTearDown(transport.close);
          final repository = PasswordRecoveryRepositoryImpl(
            client: NowaveApiClient(
              baseUrl: Uri.parse('https://api.example.invalid'),
              httpClient: transport,
            ),
            connectionChecker: _Online(),
          );
          final result = await repository.resetPassword(
            token: _resetToken,
            password: _password,
          );
          expect(
            result.getLeft().toNullable()?.code,
            'auth.passwordRecoveryResetOutcomeUnknown',
          );
          expect(requests, hasLength(1));
          expect(requests.single.followRedirects, isFalse);
        },
      );
    }
  });
}
