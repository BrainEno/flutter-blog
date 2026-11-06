import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/data/repositories/account_session_repository_impl.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
import 'package:belog/features/user/domain/entities/session_revoke_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator {
  String? user = 'user-a';
  String? token = 'fake-token-a';
  int generation = 1;
  int refreshCount = 0;
  bool refreshSucceeds = false;

  @override
  String? get accessToken => token;

  @override
  String? get activeUserId => user;

  @override
  int get sessionGeneration => generation;

  @override
  Future<bool> refresh() async {
    refreshCount++;
    if (refreshSucceeds) token = 'fake-refreshed-a';
    return refreshSucceeds;
  }

  void replace({String? withUser = 'user-b'}) {
    generation++;
    user = withUser;
    token = withUser == null ? null : 'fake-token-b';
  }
}

// Flutter's test binding can replace HTTP globally; this scoped override
// restores a real client solely for an in-process loopback redirect test.
class _LoopbackHttpOverrides extends HttpOverrides {}

const _fence = NowaveSessionFence(userId: 'user-a', generation: 1);

AccountSessionRepositoryImpl _repository(_Auth auth, MockClient httpClient) =>
    AccountSessionRepositoryImpl(
      NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        authenticator: auth,
        httpClient: httpClient,
      ),
    );

Map<String, dynamic> _row({
  String id = 'sensitive-fake-session-id',
  bool current = true,
  String? lastUsedAt = '2026-10-31T02:30:00.000Z',
}) => {
  'sessionId': id,
  'createdAt': '2026-10-30T01:00:00.000Z',
  'lastUsedAt': lastUsedAt,
  'expiresAt': '2026-12-30T01:00:00.000Z',
  'current': current,
};

http.Response _data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

http.Response _error(int status) =>
    http.Response('{"error":{"code":"UNTRUSTED"}}', status);

Failure? _failure(Either<Failure, List<AccountSession>> result) =>
    result.fold((failure) => failure, (_) => null);

Failure? _revokeFailure(Either<Failure, SessionRevokeOutcome> result) =>
    result.fold((failure) => failure, (_) => null);

SessionRevokeOutcome? _revokeOutcome(
  Either<Failure, SessionRevokeOutcome> result,
) => result.fold((_) => null, (outcome) => outcome);

Failure? _countFailure(Either<Failure, int> result) =>
    result.fold((failure) => failure, (_) => null);

int? _count(Either<Failure, int> result) =>
    result.fold((_) => null, (count) => count);

List<AccountSession>? _sessions(Either<Failure, List<AccountSession>> result) =>
    result.fold((_) => null, (sessions) => sessions);

void main() {
  test(
    'reads the exact authenticated endpoint and drops session IDs',
    () async {
      final auth = _Auth();
      final seen = <http.Request>[];
      final repository = _repository(
        auth,
        MockClient((request) async {
          seen.add(request);
          return _data({
            'sessions': [
              _row(),
              _row(
                id: 'another-sensitive-id',
                current: false,
                lastUsedAt: null,
              ),
            ],
          });
        }),
      );

      final sessions = _sessions(await repository.listSessions(_fence))!;
      expect(seen, hasLength(1));
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/me/sessions');
      expect(seen.single.followRedirects, isFalse);
      expect(seen.single.headers['authorization'], 'Bearer fake-token-a');
      expect(sessions, hasLength(2));
      expect(sessions.first.current, isTrue);
      expect(sessions.first.createdAt, DateTime.utc(2026, 10, 30, 1));
      expect(sessions.first.lastRefreshedAt, DateTime.utc(2026, 10, 31, 2, 30));
      expect(sessions[1].lastRefreshedAt, isNull);
      expect(sessions[1].current, isFalse);
      expect(sessions.toString(), isNot(contains('sensitive-fake-session-id')));
      expect(() => sessions.clear(), throwsUnsupportedError);
    },
  );

  test('accepts an empty list and an unmarked current session', () async {
    final auth = _Auth();
    var payload = <String, dynamic>{'sessions': []};
    final repository = _repository(
      auth,
      MockClient((_) async => _data(payload)),
    );
    expect(_sessions(await repository.listSessions(_fence)), isEmpty);
    payload = {
      'sessions': [_row(current: false, lastUsedAt: null)],
    };
    final sessions = _sessions(await repository.listSessions(_fence))!;
    expect(sessions.single.current, isFalse);
  });

  test('does not send without the initiating account and generation', () async {
    final auth = _Auth()..replace();
    var requests = 0;
    final repository = _repository(
      auth,
      MockClient((_) async {
        requests++;
        return _data({'sessions': []});
      }),
    );
    final failure = _failure(await repository.listSessions(_fence));
    expect(failure?.code, 'auth.sessionChanged');
    expect(requests, 0);
  });

  for (final status in [200, 401]) {
    test('a delayed $status from A is not shown or retried as B', () async {
      final auth = _Auth();
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final tokens = <String?>[];
      final repository = _repository(
        auth,
        MockClient((request) {
          tokens.add(request.headers['authorization']);
          started.complete();
          return response.future;
        }),
      );
      final pending = repository.listSessions(_fence);
      await started.future;
      auth.replace();
      response.complete(
        status == 200
            ? _data({
                'sessions': [_row()],
              })
            : http.Response(
                jsonEncode({
                  'error': {'code': 'UNAUTHENTICATED'},
                }),
                401,
              ),
      );
      final failure = _failure(await pending);
      expect(failure?.code, 'auth.sessionChanged');
      expect(tokens, ['Bearer fake-token-a']);
      expect(auth.refreshCount, 0);
      expect(failure?.cause, isNull);
    });
  }

  test(
    'an expired token can refresh and retry within the same session',
    () async {
      final auth = _Auth()..refreshSucceeds = true;
      final tokens = <String?>[];
      final repository = _repository(
        auth,
        MockClient((request) async {
          tokens.add(request.headers['authorization']);
          if (tokens.length == 1) {
            return http.Response(
              jsonEncode({
                'error': {'code': 'UNAUTHENTICATED'},
              }),
              401,
            );
          }
          return _data({
            'sessions': [_row()],
          });
        }),
      );
      expect(_sessions(await repository.listSessions(_fence)), hasLength(1));
      expect(tokens, ['Bearer fake-token-a', 'Bearer fake-refreshed-a']);
      expect(auth.refreshCount, 1);
    },
  );

  for (final entry in <int, String>{
    401: 'server.UNAUTHENTICATED',
    404: 'sessions.unavailable',
    405: 'sessions.unavailable',
    429: 'server.RATE_LIMITED',
    500: 'server.error',
  }.entries) {
    test('HTTP ${entry.key} is classified without exposing its body', () async {
      final auth = _Auth();
      final repository = _repository(
        auth,
        MockClient(
          (_) async => http.Response('private server message', entry.key),
        ),
      );
      final failure = _failure(await repository.listSessions(_fence));
      expect(failure?.code, entry.value);
      expect(failure?.message, isNot(contains('private server message')));
      expect(failure?.cause, isNull);
    });
  }

  test(
    'a redirect cannot become data or forward the authorization header',
    () async {
      final auth = _Auth();
      final requests = <http.Request>[];
      final repository = _repository(
        auth,
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'data': {
                'sessions': [_row()],
              },
            }),
            302,
            headers: {'location': 'https://other.example.invalid/capture'},
          );
        }),
      );
      final result = await repository.listSessions(_fence);
      expect(_failure(result)?.code, 'server.error');
      expect(_sessions(result), isNull);
      expect(requests, hasLength(1));
      expect(requests.single.followRedirects, isFalse);
    },
  );

  test(
    'the real IO client does not follow an authenticated redirect',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final paths = <String>[];
        final subscription = server.listen((request) async {
          paths.add(request.uri.path);
          if (request.uri.path == '/api/v1/me/sessions') {
            request.response.statusCode = 302;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              'http://127.0.0.1:${server.port}/redirect-target',
            );
            request.response.write(
              jsonEncode({
                'data': {
                  'sessions': [_row()],
                },
              }),
            );
          } else {
            request.response.write(
              jsonEncode({
                'data': {'sessions': []},
              }),
            );
          }
          await request.response.close();
        });
        final rawClient = HttpClient()..findProxy = (_) => 'DIRECT';
        final ioClient = IOClient(rawClient);
        try {
          final repository = AccountSessionRepositoryImpl(
            NowaveApiClient(
              baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
              authenticator: _Auth(),
              httpClient: ioClient,
              timeout: const Duration(seconds: 5),
            ),
          );
          final result = await repository.listSessions(_fence);
          expect(_failure(result)?.code, 'server.error');
          expect(_sessions(result), isNull);
          expect(paths, ['/api/v1/me/sessions']);
        } finally {
          ioClient.close();
          await subscription.cancel();
          await server.close(force: true);
        }
      }, _LoopbackHttpOverrides());
    },
  );

  test('offline and timeout failures are not empty lists', () async {
    final auth = _Auth();
    final offline = _repository(
      auth,
      MockClient((_) async => throw const SocketException('offline')),
    );
    final timeout = _repository(
      auth,
      MockClient((_) async => throw TimeoutException('timeout')),
    );
    expect(
      _failure(await offline.listSessions(_fence))?.code,
      'network.unavailable',
    );
    expect(
      _failure(await timeout.listSessions(_fence))?.code,
      'network.timeout',
    );
  });

  test(
    'malformed responses are rejected without leaking the payload',
    () async {
      final auth = _Auth();
      final badRows = [
        {'sessions': 'not a list'},
        {
          'sessions': [
            <String, dynamic>{..._row()}..remove('sessionId'),
          ],
        },
        {
          'sessions': [
            <String, dynamic>{..._row(), 'current': 'yes'},
          ],
        },
        {
          'sessions': [
            <String, dynamic>{..._row(), 'createdAt': 'invalid'},
          ],
        },
        {
          'sessions': [
            <String, dynamic>{..._row(), 'lastUsedAt': 'invalid'},
          ],
        },
        {
          'sessions': [
            <String, dynamic>{..._row(), 'createdAt': '2026-10-30T01:00:00'},
          ],
        },
        {
          'sessions': [_row(), _row()],
        },
        {'sessions': List.generate(51, (_) => _row(current: false))},
      ];
      for (final payload in badRows) {
        final repository = _repository(
          auth,
          MockClient((_) async => _data(payload)),
        );
        final failure = _failure(await repository.listSessions(_fence));
        expect(failure?.code, 'client.parse');
        expect(failure?.cause, isNull);
      }
      final invalidJson = _repository(
        auth,
        MockClient((_) async => http.Response('{private', 200)),
      );
      final failure = _failure(await invalidJson.listSessions(_fence));
      expect(failure?.code, 'client.parse');
      expect(failure?.message, isNot(contains('private')));
    },
  );

  test('ending one session names it in the path and sends no body', () async {
    final auth = _Auth();
    final seen = <http.Request>[];
    final repository = _repository(
      auth,
      MockClient((request) async {
        seen.add(request);
        return _data({'ok': true});
      }),
    );

    final result = await repository.revokeSession(_fence, 'session-2');

    expect(_revokeOutcome(result), SessionRevokeOutcome.ended);
    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/api/v1/me/sessions/session-2');
    expect(seen.single.body, isEmpty);
    expect(seen.single.headers.containsKey('content-type'), isFalse);
    expect(seen.single.followRedirects, isFalse);
    expect(seen.single.headers['authorization'], 'Bearer fake-token-a');
  });

  test('an id is encoded and never resolves to another route', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data({'ok': true});
      }),
    );

    await repository.revokeSession(_fence, 'a/b?c#d');
    expect(seen.single.url.path, '/api/v1/me/sessions/a%2Fb%3Fc%23d');

    for (final bad in ['', ' session-2', 'session-2 ', '.', '..']) {
      final failure = _revokeFailure(
        await repository.revokeSession(_fence, bad),
      );
      expect(failure?.code, 'sessions.invalidSession', reason: bad);
    }
    expect(seen, hasLength(1));
  });

  test(
    'a session that is already gone is the goal state, not an error',
    () async {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => _error(404)),
      );

      final result = await repository.revokeSession(_fence, 'session-2');

      expect(_revokeOutcome(result), SessionRevokeOutcome.alreadyEnded);
    },
  );

  test('revocation failures carry a code, never the raw answer', () async {
    final cases = <int, String>{
      400: 'sessions.revokeRejected',
      401: 'server.UNAUTHENTICATED',
      403: 'server.permission',
      405: 'sessions.revokeUnavailable',
      429: 'server.RATE_LIMITED',
      500: 'sessions.revokeUnknown',
      503: 'sessions.revokeUnknown',
    };
    for (final entry in cases.entries) {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => _error(entry.key)),
      );
      final failure = _revokeFailure(
        await repository.revokeSession(_fence, 'session-2'),
      );
      expect(failure?.code, entry.value, reason: '${entry.key}');
      expect(failure?.cause, isNull, reason: '${entry.key}');
    }
  });

  test('a lost answer is uncertain: the session may already be gone', () async {
    for (final repository in [
      _repository(
        _Auth(),
        MockClient((_) async => throw const SocketException('fixture')),
      ),
      _repository(_Auth(), MockClient((_) async => _data({'ok': false}))),
    ]) {
      final failure = _revokeFailure(
        await repository.revokeSession(_fence, 'session-2'),
      );
      expect(failure?.code, 'sessions.revokeUnknown');
    }
  });

  test('a stale fence never reaches the server', () async {
    final auth = _Auth();
    var calls = 0;
    final repository = _repository(
      auth,
      MockClient((_) async {
        calls++;
        return _data({'ok': true});
      }),
    );
    auth.replace();

    final failure = _revokeFailure(
      await repository.revokeSession(_fence, 'session-2'),
    );

    expect(failure?.code, 'auth.sessionChanged');
    expect(failure?.kind, FailureKind.auth);
    expect(calls, 0);
  });

  test('ending the others reports how many went', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data({'ok': true, 'revokedSessions': 3});
      }),
    );

    final result = await repository.revokeOtherSessions(_fence);

    expect(_count(result), 3);
    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/api/v1/me/sessions');
    expect(seen.single.followRedirects, isFalse);

    final none = _repository(
      _Auth(),
      MockClient((_) async => _data({'ok': true, 'revokedSessions': 0})),
    );
    expect(_count(await none.revokeOtherSessions(_fence)), 0);
  });

  test('an unreadable count is not reported as zero', () async {
    for (final payload in [
      {'ok': true},
      {'ok': true, 'revokedSessions': 'three'},
      {'ok': true, 'revokedSessions': -1},
      {'ok': false, 'revokedSessions': 2},
    ]) {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => _data(payload)),
      );
      expect(
        _countFailure(await repository.revokeOtherSessions(_fence))?.code,
        'sessions.revokeUnknown',
        reason: '$payload',
      );
    }
  });

  test(
    'an old deployment says "not supported", not "nothing to end"',
    () async {
      for (final status in [404, 405]) {
        final repository = _repository(
          _Auth(),
          MockClient((_) async => _error(status)),
        );
        expect(
          _countFailure(await repository.revokeOtherSessions(_fence))?.code,
          'sessions.revokeUnavailable',
          reason: '$status',
        );
      }
    },
  );

  test(
    'the real IO client sends a bodyless DELETE the server accepts',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final methods = <String>[];
        final lengths = <String?>[];
        final encodings = <String?>[];
        final bodies = <int>[];
        final subscription = server.listen((request) async {
          methods.add(request.method);
          lengths.add(request.headers.value(HttpHeaders.contentLengthHeader));
          encodings.add(
            request.headers.value(HttpHeaders.transferEncodingHeader),
          );
          bodies.add(
            await request.fold<int>(0, (sum, chunk) => sum + chunk.length),
          );
          request.response.write(
            jsonEncode({
              'data': {'ok': true},
            }),
          );
          await request.response.close();
        });
        final rawClient = HttpClient()..findProxy = (_) => 'DIRECT';
        try {
          final repository = AccountSessionRepositoryImpl(
            NowaveApiClient(
              baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
              authenticator: _Auth(),
              httpClient: IOClient(rawClient),
              timeout: const Duration(seconds: 5),
            ),
          );
          expect(
            _revokeOutcome(await repository.revokeSession(_fence, 'session-2')),
            SessionRevokeOutcome.ended,
          );
          // This fixture has no count, so the second call is unreadable.
          expect(
            _countFailure(await repository.revokeOtherSessions(_fence))?.code,
            'sessions.revokeUnknown',
          );
        } finally {
          await subscription.cancel();
          await server.close(force: true);
        }
        // `DELETE /me/sessions/:id` answers 400 to any request carrying a body
        // header, so the transport must not add `content-length: 0`.
        expect(methods, ['DELETE', 'DELETE']);
        expect(lengths, [null, null]);
        expect(encodings, [null, null]);
        expect(bodies, [0, 0]);
      }, _LoopbackHttpOverrides());
    },
  );
}
