import 'dart:async';
import 'dart:convert';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _BoundAuth implements NowaveSessionBoundAuthenticator {
  String? token = 'token-A';
  int generation = 1;
  int refreshCalls = 0;
  Completer<void>? refreshStarted;
  Completer<void>? refreshGate;

  @override
  String? get accessToken => token;

  @override
  int get sessionGeneration => generation;

  void switchToB() {
    generation++;
    token = 'token-B';
  }

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    refreshStarted?.complete();
    final gate = refreshGate;
    if (gate != null) await gate.future;
    token = 'refreshed';
    return true;
  }
}

class _RejectedRefreshAuth extends _BoundAuth {
  @override
  Future<bool> refresh() async {
    refreshCalls++;
    generation++;
    token = null;
    return false;
  }
}

class _ExpiredProactiveAuth extends _BoundAuth
    implements NowaveProactiveAuthenticator {
  @override
  Future<bool> ensureFreshAccess() async {
    generation++;
    token = null;
    return false;
  }
}

class _ProactiveBoundAuth extends _BoundAuth
    implements NowaveProactiveAuthenticator {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<bool> ensureFreshAccess() async {
    started.complete();
    await gate.future;
    return false;
  }
}

NowaveApiClient _client(_BoundAuth auth, MockClient client) => NowaveApiClient(
  baseUrl: Uri.parse('https://api.example.invalid'),
  authenticator: auth,
  httpClient: client,
);

http.Response _unauthorized() => http.Response(
  jsonEncode({
    'error': {'code': 'UNAUTHENTICATED', 'message': 'expired'},
  }),
  401,
);

Matcher get _sessionChanged =>
    isA<NowaveApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED');

void main() {
  for (final status in [200, 401]) {
    test(
      'a $status from the previous account is not reused or presented',
      () async {
        final auth = _BoundAuth();
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final seen = <String?>[];
        final client = _client(
          auth,
          MockClient((request) {
            seen.add(request.headers['authorization']);
            started.complete();
            return response.future;
          }),
        );
        final request = client.postJson('/articles', {'title': 'A'});
        final expectation = expectLater(request, throwsA(_sessionChanged));
        await started.future;
        auth.switchToB();
        response.complete(
          status == 401
              ? _unauthorized()
              : http.Response(
                  jsonEncode({
                    'data': {'id': 'A'},
                  }),
                  200,
                ),
        );
        await expectation;

        expect(seen, ['Bearer token-A']);
        expect(auth.refreshCalls, 0);
      },
    );
  }

  test(
    'account switch while refreshing cannot retry with the new token',
    () async {
      final auth = _BoundAuth()
        ..refreshStarted = Completer<void>()
        ..refreshGate = Completer<void>();
      var requests = 0;
      final client = _client(
        auth,
        MockClient((_) async {
          requests++;
          return _unauthorized();
        }),
      );
      final pending = client.postJson('/articles', {'title': 'A'});
      final expectation = expectLater(pending, throwsA(_sessionChanged));
      await auth.refreshStarted!.future;
      auth.switchToB();
      auth.refreshGate!.complete();
      await expectation;
      expect(requests, 1);
    },
  );

  test(
    'a token already rotated in the same session is reused without another refresh',
    () async {
      final auth = _BoundAuth();
      final started = Completer<void>();
      final first = Completer<http.Response>();
      final seen = <String?>[];
      final client = _client(
        auth,
        MockClient((request) {
          seen.add(request.headers['authorization']);
          if (seen.length == 1) {
            started.complete();
            return first.future;
          }
          return Future.value(
            http.Response(
              jsonEncode({
                'data': {'ok': true},
              }),
              200,
            ),
          );
        }),
      );
      final pending = client.getJson('/me/profile');
      await started.future;
      auth.token = 'token-A-rotated';
      first.complete(_unauthorized());

      expect((await pending as Map)['ok'], isTrue);
      expect(seen, ['Bearer token-A', 'Bearer token-A-rotated']);
      expect(auth.refreshCalls, 0);
    },
  );

  test(
    'a switch during proactive refresh prevents the original request',
    () async {
      final auth = _ProactiveBoundAuth();
      var requests = 0;
      final client = _client(
        auth,
        MockClient((_) async {
          requests++;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );
      final pending = client.getJson('/me/profile');
      final expectation = expectLater(pending, throwsA(_sessionChanged));
      await auth.started.future;
      auth.switchToB();
      auth.gate.complete();
      await expectation;
      expect(requests, 0);
    },
  );

  test(
    'a rejected refresh returns the original 401 without retrying',
    () async {
      final auth = _RejectedRefreshAuth();
      var requests = 0;
      final client = _client(
        auth,
        MockClient((_) async {
          requests++;
          return _unauthorized();
        }),
      );
      await expectLater(
        client.getJson('/me/profile'),
        throwsA(
          isA<NowaveApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.code, 'code', 'UNAUTHENTICATED'),
        ),
      );
      expect(requests, 1);
      expect(auth.refreshCalls, 1);
    },
  );

  test(
    'an expired session before sending reports 401 without a request',
    () async {
      final auth = _ExpiredProactiveAuth();
      var requests = 0;
      final client = _client(
        auth,
        MockClient((_) async {
          requests++;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );
      await expectLater(
        client.postJson('/articles', {'title': 'not sent'}),
        throwsA(
          isA<NowaveApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.code, 'code', 'UNAUTHENTICATED'),
        ),
      );
      expect(requests, 0);
    },
  );

  test(
    'sign-out during an already sent write remains an uncertain result',
    () async {
      final auth = _BoundAuth();
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final client = _client(
        auth,
        MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = client.postJson('/articles', {'title': 'A'});
      final expectation = expectLater(pending, throwsA(_sessionChanged));
      await started.future;
      auth.generation++;
      auth.token = null;
      response.complete(
        http.Response(
          jsonEncode({
            'data': {'id': 'A'},
          }),
          200,
        ),
      );
      await expectation;
    },
  );

  test('session-change errors are safely classified for the UI', () {
    final failure = mapErrorToFailure(
      const NowaveApiException(
        statusCode: 409,
        code: 'SESSION_CHANGED',
        message: 'private detail',
      ),
    );
    expect(failure.kind, FailureKind.auth);
    expect(failure.code, 'auth.sessionChanged');
    expect(failure.message, isNot(contains('private detail')));
  });
}
