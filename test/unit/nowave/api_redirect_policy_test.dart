import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/network/connectivity_evidence.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.invalid';
const _token = 'local-test-token';
const _secret = 'local-test-password';
const _target = 'https://attacker.example.invalid/collect?private=secret';
const _fence = NowaveSessionFence(userId: 'author', generation: 1);

class _Authenticator implements NowaveViewerAuthenticator {
  @override
  String? accessToken = _token;
  @override
  String? activeUserId = 'author';
  @override
  int sessionGeneration = 1;
  int refreshCalls = 0;
  @override
  Future<bool> refresh() async {
    refreshCalls++;
    accessToken = 'refreshed-token';
    return true;
  }
}

class _Evidence implements ConnectivityEvidence {
  final responses = <Uri>[];
  final failures = <Uri>[];
  @override
  void recordResponse(Uri requestUri) => responses.add(requestUri);
  @override
  void recordTransportFailure(Uri requestUri) => failures.add(requestUri);
}

class _LoopbackOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

typedef _Invoke = Future<dynamic> Function(NowaveApiClient client);

class _Operation {
  const _Operation(
    this.name,
    this.method,
    this.path,
    this.invoke, {
    this.authenticated = true,
  });
  final String name;
  final String method;
  final String path;
  final _Invoke invoke;
  final bool authenticated;
}

final _operations = <_Operation>[
  _Operation(
    'GET',
    'GET',
    '/me/profile',
    (client) => client.getJson('/me/profile'),
  ),
  _Operation(
    'POST',
    'POST',
    '/articles',
    (client) => client.postJson('/articles', {'title': 'private'}),
  ),
  _Operation(
    'PUT',
    'PUT',
    '/articles/example',
    (client) => client.putJson('/articles/example', {'content': 'private'}),
  ),
  _Operation(
    'PATCH',
    'PATCH',
    '/me/profile',
    (client) => client.patchJson('/me/profile', {'name': 'private'}),
  ),
  _Operation(
    'DELETE',
    'DELETE',
    '/me/sessions/one',
    (client) => client.deleteJson('/me/sessions/one'),
  ),
  _Operation(
    'media',
    'POST',
    '/me/media',
    (client) => client.uploadMedia(Uint8List.fromList([1, 2, 3]), 'image/png'),
  ),
  _Operation(
    'login',
    'POST',
    '/auth/login',
    (client) => client.postJson('/auth/login', {
      'email': 'user@example.invalid',
      'password': _secret,
    }, authenticate: false),
    authenticated: false,
  ),
  _Operation(
    'refresh',
    'POST',
    '/auth/refresh',
    (client) => client.postJson('/auth/refresh', {
      'refreshToken': _secret,
    }, authenticate: false),
    authenticated: false,
  ),
  _Operation(
    'forgot password',
    'POST',
    '/auth/forgot-password',
    (client) => client.postJson('/auth/forgot-password', {
      'email': 'user@example.invalid',
    }, authenticate: false),
    authenticated: false,
  ),
  _Operation(
    'reset password',
    'POST',
    '/auth/reset-password',
    (client) => client.postJson('/auth/reset-password', {
      'token': _secret,
      'password': _secret,
    }, authenticate: false),
    authenticated: false,
  ),
  _Operation(
    'viewer GET',
    'GET',
    '/me/profile',
    (client) =>
        client.getJsonForViewer('/me/profile', expectedUserId: 'author'),
  ),
  _Operation(
    'viewer PUT once',
    'PUT',
    '/me/email',
    (client) => client.putJsonForViewerOnce(
      '/me/email',
      {'password': _secret},
      expectedUserId: 'author',
      expectedSessionGeneration: 1,
    ),
  ),
  _Operation(
    'viewer POST once',
    'POST',
    '/me/email/verify',
    (client) => client.postJsonForViewerOnce(
      '/me/email/verify',
      {'token': _secret},
      expectedUserId: 'author',
      expectedSessionGeneration: 1,
    ),
  ),
  _Operation(
    'fenced GET',
    'GET',
    '/me/profile',
    (client) => client.getJson('/me/profile', sessionFence: _fence),
  ),
  _Operation(
    'fenced upload',
    'POST',
    '/me/media',
    (client) => client.uploadMedia(
      Uint8List.fromList([1, 2, 3]),
      'image/png',
      sessionFence: _fence,
    ),
  ),
];

Matcher _redirect(int status) => isA<NowaveApiException>()
    .having((error) => error.statusCode, 'status', status)
    .having((error) => error.code, 'code', 'HTTP_REDIRECT');

void main() {
  group('redirect policy for every public API operation', () {
    for (final status in [302, 307]) {
      for (final operation in _operations) {
        test(
          '${operation.name} refuses HTTP $status at the original endpoint',
          () async {
            final auth = _Authenticator();
            final seen = <http.Request>[];
            final transport = MockClient((request) async {
              seen.add(request);
              return http.Response(
                '{"data":{"misleading":true}}',
                status,
                headers: {'location': _target},
              );
            });
            addTearDown(transport.close);
            final client = NowaveApiClient(
              baseUrl: Uri.parse(_baseUrl),
              authenticator: auth,
              httpClient: transport,
            );
            await expectLater(
              operation.invoke(client),
              throwsA(_redirect(status)),
            );
            expect(seen, hasLength(1));
            expect(seen.single.method, operation.method);
            expect(seen.single.url.path, '/api/v1${operation.path}');
            expect(seen.single.followRedirects, isFalse);
            expect(
              seen.single.headers['authorization'],
              operation.authenticated ? 'Bearer $_token' : null,
            );
            expect(auth.refreshCalls, 0);
          },
        );
      }
    }

    for (final status in [300, 301, 303, 304, 305, 306, 308, 399]) {
      test(
        'all 3xx responses fail closed, including $status without Location',
        () async {
          var calls = 0;
          final client = NowaveApiClient(
            baseUrl: Uri.parse(_baseUrl),
            httpClient: MockClient((request) async {
              calls++;
              expect(request.followRedirects, isFalse);
              return http.Response('{"data":"not a success"}', status);
            }),
          );
          await expectLater(
            client.getJson('/public'),
            throwsA(_redirect(status)),
          );
          expect(calls, 1);
        },
      );
    }

    test(
      'explicitly opting into redirects is rejected before any transport',
      () async {
        var calls = 0;
        final auth = _Authenticator();
        final client = NowaveApiClient(
          baseUrl: Uri.parse(_baseUrl),
          authenticator: auth,
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('{"data":null}', 200);
          }),
        );
        final callsWithOptIn = <Future<dynamic> Function()>[
          () => client.getJson('/me/profile', followRedirects: true),
          () => client.postJson(
            '/auth/login',
            {'password': _secret},
            authenticate: false,
            followRedirects: true,
          ),
          () => client.patchJson('/me/profile', {
            'name': 'x',
          }, followRedirects: true),
          () => client.deleteJson('/me/session', followRedirects: true),
        ];
        for (final invoke in callsWithOptIn) {
          await expectLater(invoke(), throwsArgumentError);
        }
        expect(calls, 0);
        expect(auth.refreshCalls, 0);
      },
    );

    test(
      'legacy explicit false remains accepted and successful 2xx decodes',
      () async {
        final seen = <http.Request>[];
        final client = NowaveApiClient(
          baseUrl: Uri.parse(_baseUrl),
          httpClient: MockClient((request) async {
            seen.add(request);
            return http.Response('{"data":{"ok":true}}', 200);
          }),
        );
        expect(
          (await client.getJson('/public', followRedirects: false))['ok'],
          isTrue,
        );
        expect(
          (await client.postJson('/write', {}, followRedirects: false))['ok'],
          isTrue,
        );
        expect(
          (await client.patchJson('/write', {}, followRedirects: false))['ok'],
          isTrue,
        );
        expect(
          (await client.deleteJson('/write', followRedirects: false))['ok'],
          isTrue,
        );
        expect(seen.every((request) => !request.followRedirects), isTrue);
      },
    );

    test('redirect body and Location are not decoded or surfaced', () async {
      final evidence = _Evidence();
      final transport = MockClient(
        (_) async => http.Response(
          '{"error":{"code":"TOKEN_$_secret","message":"$_token"}}',
          302,
          headers: {'location': _target},
        ),
      );
      final client = NowaveApiClient(
        baseUrl: Uri.parse(_baseUrl),
        httpClient: transport,
        connectivityEvidence: evidence,
      );
      try {
        await client.getJson('/me/profile', query: {'secret': _secret});
        fail('expected redirect');
      } on NowaveApiException catch (error) {
        expect(error.code, 'HTTP_REDIRECT');
        expect(error.message, contains('/api/v1/me/profile'));
        expect(error.message, isNot(contains(_secret)));
        expect(error.message, isNot(contains(_token)));
        expect(error.message, isNot(contains(_target)));
        expect(evidence.responses.single.path, '/api/v1/me/profile');
        expect(evidence.failures, isEmpty);
      }
    });

    test(
      'redirect can fail at headers without waiting for a stalled body',
      () async {
        final body = StreamController<List<int>>();
        var cancelled = false;
        final transport = MockClient.streaming((request, requestBody) async {
          body.onCancel = () {
            cancelled = true;
          };
          return http.StreamedResponse(
            body.stream,
            307,
            headers: {'location': _target},
          );
        });
        addTearDown(() async {
          transport.close();
          await body.close();
        });
        final client = NowaveApiClient(
          baseUrl: Uri.parse(_baseUrl),
          httpClient: transport,
          timeout: const Duration(seconds: 1),
        );
        await expectLater(
          client.getJson('/me/profile'),
          throwsA(_redirect(307)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(cancelled, isTrue);
      },
    );
  });

  group('refresh and identity fences', () {
    test(
      'a redirect never initiates token refresh or request replay',
      () async {
        final auth = _Authenticator();
        var calls = 0;
        final client = NowaveApiClient(
          baseUrl: Uri.parse(_baseUrl),
          authenticator: auth,
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('', 307, headers: {'location': _target});
          }),
        );
        await expectLater(
          client.postJson('/articles', {'title': 'draft'}),
          throwsA(_redirect(307)),
        );
        expect(calls, 1);
        expect(auth.refreshCalls, 0);
      },
    );

    test(
      'a replay following a legitimate 401 still rejects redirect',
      () async {
        final auth = _Authenticator();
        final sent = <String?>[];
        final client = NowaveApiClient(
          baseUrl: Uri.parse(_baseUrl),
          authenticator: auth,
          httpClient: MockClient((request) async {
            expect(request.followRedirects, isFalse);
            sent.add(request.headers['authorization']);
            return sent.length == 1
                ? http.Response('{"error":{"code":"UNAUTHENTICATED"}}', 401)
                : http.Response('', 302, headers: {'location': _target});
          }),
        );
        await expectLater(
          client.getJson('/me/profile'),
          throwsA(_redirect(302)),
        );
        expect(sent, ['Bearer $_token', 'Bearer refreshed-token']);
        expect(auth.refreshCalls, 1);
      },
    );

    test(
      'viewer identity change takes precedence over a late redirect',
      () async {
        final auth = _Authenticator();
        final gate = Completer<http.Response>();
        final started = Completer<void>();
        final client = NowaveApiClient(
          baseUrl: Uri.parse(_baseUrl),
          authenticator: auth,
          httpClient: MockClient((_) {
            started.complete();
            return gate.future;
          }),
        );
        final request = client.getJsonForViewer(
          '/me/profile',
          expectedUserId: 'author',
        );
        await started.future;
        auth.activeUserId = 'other';
        auth.sessionGeneration++;
        gate.complete(http.Response('', 307, headers: {'location': _target}));
        await expectLater(
          request,
          throwsA(
            isA<NowaveApiException>().having(
              (e) => e.code,
              'code',
              'SESSION_CHANGED',
            ),
          ),
        );
        expect(auth.refreshCalls, 0);
      },
    );

    test('anonymous credential POST never refreshes on a redirect', () async {
      final auth = _Authenticator();
      final client = NowaveApiClient(
        baseUrl: Uri.parse(_baseUrl),
        authenticator: auth,
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], isNull);
          return http.Response('', 302, headers: {'location': _target});
        }),
      );
      await expectLater(
        client.postJson('/auth/login', {
          'password': _secret,
        }, authenticate: false),
        throwsA(_redirect(302)),
      );
      expect(auth.refreshCalls, 0);
    });
  });

  group('real IO transport redirect isolation', () {
    for (final status in [302, 307]) {
      for (final sameOrigin in [false, true]) {
        for (final operation in _operations.take(10)) {
          test(
            '${operation.name} $status ${sameOrigin ? 'same' : 'cross'} origin sends only original request',
            () async {
              await HttpOverrides.runWithHttpOverrides(() async {
                final source = await HttpServer.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                final sink = await HttpServer.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                final requests = <String>[];
                final targetRequests = <String>[];
                final bodies = <String>[];
                final headers = <String?>[];
                final sinkSubscription = sink.listen((request) async {
                  targetRequests.add(request.uri.path);
                  await request.drain<void>();
                  request.response.write('{"data":{"ok":true}}');
                  await request.response.close();
                });
                final sourceSubscription = source.listen((request) async {
                  requests.add(request.uri.path);
                  headers.add(request.headers.value('authorization'));
                  bodies.add(await utf8.decodeStream(request));
                  if (request.uri.path == '/redirect-target') {
                    targetRequests.add(request.uri.path);
                    request.response.write('{"data":{"ok":true}}');
                  } else {
                    request.response.statusCode = status;
                    request.response.headers.set(
                      HttpHeaders.locationHeader,
                      'http://127.0.0.1:${sameOrigin ? source.port : sink.port}/redirect-target',
                    );
                    request.response.write('{"data":{"ok":true}}');
                  }
                  try {
                    await request.response.close();
                  } on HttpException {
                    /* client cancelled */
                  }
                });
                final io = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
                final auth = _Authenticator();
                try {
                  final client = NowaveApiClient(
                    baseUrl: Uri.parse('http://127.0.0.1:${source.port}'),
                    authenticator: auth,
                    httpClient: io,
                    timeout: const Duration(seconds: 5),
                  );
                  await expectLater(
                    operation.invoke(client),
                    throwsA(_redirect(status)),
                  );
                  expect(requests, ['/api/v1${operation.path}']);
                  expect(targetRequests, isEmpty);
                  expect(
                    headers.single,
                    operation.authenticated ? 'Bearer $_token' : null,
                  );
                  if (operation.name == 'login') {
                    expect(bodies.single, contains(_secret));
                  }
                  expect(auth.refreshCalls, 0);
                } finally {
                  io.close();
                  await sourceSubscription.cancel();
                  await sinkSubscription.cancel();
                  await source.close(force: true);
                  await sink.close(force: true);
                }
              }, _LoopbackOverrides());
            },
          );
        }
      }
    }
  });

  test('diagnostics do not record redirect Location or credentials', () async {
    AppLogger.clearDiagnostics();
    addTearDown(AppLogger.clearDiagnostics);
    final client = NowaveApiClient(
      baseUrl: Uri.parse(_baseUrl),
      authenticator: _Authenticator(),
      httpClient: MockClient(
        (_) async =>
            http.Response(_secret, 307, headers: {'location': _target}),
      ),
    );
    await expectLater(
      client.postJson('/auth/login', {
        'password': _secret,
      }, authenticate: false),
      throwsA(_redirect(307)),
    );
    final diagnostics = AppLogger.diagnosticsReport();
    expect(diagnostics, isNot(contains(_secret)));
    expect(diagnostics, isNot(contains(_token)));
    expect(diagnostics, isNot(contains(_target)));
  });
}
