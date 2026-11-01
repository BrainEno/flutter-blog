import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/data/repositories/account_security_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Session implements NowaveViewerAuthenticator {
  String? userId = 'user-a';
  String? token = 'access-a';
  int generation = 1;
  int refreshCalls = 0;

  @override
  String? get accessToken => token;
  @override
  String? get activeUserId => userId;
  @override
  int get sessionGeneration => generation;

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    token = 'refreshed-a';
    return true;
  }

  void switchToB() {
    generation++;
    userId = 'user-b';
    token = 'access-b';
  }
}

class _Connection implements ConnectionChecker {
  _Connection(this.connected);
  bool connected;
  @override
  Future<bool> get isConnected async => connected;
}

http.Response _ok(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);
http.Response _error(int status, String code, {String message = 'rejected'}) =>
    http.Response(
      jsonEncode({
        'error': {'code': code, 'message': message},
      }),
      status,
    );

AccountSecurityRepositoryImpl _repository(
  _Session session,
  MockClient httpClient, {
  _Connection? connection,
  Duration timeout = const Duration(seconds: 5),
}) => AccountSecurityRepositoryImpl(
  client: NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: session,
    httpClient: httpClient,
    timeout: timeout,
  ),
  session: session,
  connectionChecker: connection ?? _Connection(true),
);

Future<Either<Failure, void>> _change(
  AccountSecurityRepositoryImpl repository, {
  String userId = 'user-a',
  int generation = 1,
  String current = 'current password',
  String next = 'a new password',
}) => repository.changePassword(
  expectedUserId: userId,
  expectedSessionGeneration: generation,
  currentPassword: current,
  newPassword: next,
);

Failure? _failure(Either<Failure, void> result) =>
    result.fold<Failure?>((failure) => failure, (_) => null);

void main() {
  test(
    'preflights identity then sends exact credentials once, without redirects',
    () async {
      final session = _Session();
      final requests = <http.Request>[];
      final repository = _repository(
        session,
        MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          return _ok({'ok': true, 'revokedSessions': 2});
        }),
      );
      final result = await _change(
        repository,
        current: ' current password ',
        next: '  new password  ',
      );
      expect(result.isRight(), isTrue);
      expect(requests.map((request) => request.method), ['GET', 'PUT']);
      expect(requests[0].url.path, '/api/v1/me');
      expect(requests[1].url.path, '/api/v1/me/password');
      expect(requests[1].headers['authorization'], 'Bearer access-a');
      expect(requests[1].followRedirects, isFalse);
      expect(jsonDecode(requests[1].body), {
        'currentPassword': ' current password ',
        'newPassword': '  new password  ',
      });
      expect(session.refreshCalls, 0);
    },
  );

  test(
    'wrong password or expired session gets one PUT and no refresh',
    () async {
      final session = _Session();
      final methods = <String>[];
      final repository = _repository(
        session,
        MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          return _error(401, 'UNAUTHENTICATED', message: 'current password');
        }),
      );
      AppLogger.clearDiagnostics();
      final failure = _failure(await _change(repository));
      expect(failure?.code, 'auth.passwordRejected');
      expect(failure?.cause, isNull);
      expect(failure.toString(), isNot(contains('current password')));
      expect(
        AppLogger.diagnosticsReport(),
        isNot(contains('current password')),
      );
      expect(methods, ['GET', 'PUT']);
      expect(session.refreshCalls, 0);
    },
  );

  test('only the safe preflight GET can refresh and retry on a 401', () async {
    final session = _Session();
    final methods = <String>[];
    final authHeaders = <String?>[];
    var gets = 0;
    final repository = _repository(
      session,
      MockClient((request) async {
        methods.add(request.method);
        authHeaders.add(request.headers['authorization']);
        if (request.method == 'PUT') return _ok({'ok': true});
        gets++;
        return gets == 1
            ? _error(401, 'UNAUTHENTICATED')
            : _ok({'id': 'user-a'});
      }),
    );
    expect((await _change(repository)).isRight(), isTrue);
    expect(methods, ['GET', 'GET', 'PUT']);
    expect(authHeaders, [
      'Bearer access-a',
      'Bearer refreshed-a',
      'Bearer refreshed-a',
    ]);
    expect(session.refreshCalls, 1);
  });

  test(
    'offline, invalid inputs, and mismatched identity never send credentials',
    () async {
      final session = _Session();
      var calls = 0;
      final connection = _Connection(false);
      final repository = _repository(
        session,
        MockClient((_) async {
          calls++;
          return _ok({'id': 'wrong-user'});
        }),
        connection: connection,
      );
      expect(
        _failure(await _change(repository, next: 'short'))?.code,
        'server.BAD_USER_INPUT',
      );
      expect(_failure(await _change(repository))?.code, 'network.offline');
      expect(calls, 0);
      connection.connected = true;
      expect(
        _failure(await _change(repository))?.code,
        'auth.passwordIdentityUnconfirmed',
      );
      expect(calls, 1);
    },
  );

  test(
    'preflight failures do not report an uncertain password write',
    () async {
      final session = _Session();
      final methods = <String>[];
      final repository = _repository(
        session,
        MockClient((request) async {
          methods.add(request.method);
          return _error(503, 'SERVICE_UNAVAILABLE');
        }),
      );
      final failure = _failure(await _change(repository));
      expect(failure?.code, 'server.SERVICE_UNAVAILABLE');
      expect(failure?.cause, isNull);
      expect(methods, ['GET']);
    },
  );

  for (final entry in <int, String>{
    400: 'server.BAD_USER_INPUT',
    401: 'auth.passwordRejected',
    403: 'server.permission',
    404: 'auth.passwordUnsupported',
    405: 'auth.passwordUnsupported',
    429: 'auth.rateLimited',
    500: 'auth.passwordOutcomeUnknown',
    503: 'auth.passwordOutcomeUnknown',
  }.entries) {
    test(
      'password endpoint status ${entry.key} is safely classified',
      () async {
        final session = _Session();
        var puts = 0;
        final repository = _repository(
          session,
          MockClient((request) async {
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            puts++;
            return _error(entry.key, 'UNTRUSTED', message: 'a new password');
          }),
        );
        final failure = _failure(await _change(repository));
        expect(failure?.code, entry.value);
        expect(failure?.cause, isNull);
        expect(failure.toString(), isNot(contains('a new password')));
        expect(puts, 1);
        expect(session.refreshCalls, 0);
      },
    );
  }

  test(
    'malformed success, redirect, and dropped connection are uncertain',
    () async {
      for (final response in [
        http.Response('not json', 200),
        _ok({'ok': false}),
        http.Response(
          '',
          307,
          headers: {'location': 'https://elsewhere.invalid'},
        ),
      ]) {
        var calls = 0;
        final repository = _repository(
          _Session(),
          MockClient((request) async {
            calls++;
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            expect(request.followRedirects, isFalse);
            return response;
          }),
        );
        expect(
          _failure(await _change(repository))?.code,
          'auth.passwordOutcomeUnknown',
        );
        expect(calls, 2);
      }
      final repository = _repository(
        _Session(),
        MockClient((request) async {
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          throw const SocketException('fixture transport error');
        }),
      );
      expect(
        _failure(await _change(repository))?.code,
        'auth.passwordOutcomeUnknown',
      );
    },
  );

  test('a timeout after the PUT is uncertain and never retried', () async {
    final session = _Session();
    var puts = 0;
    final never = Completer<http.Response>();
    final repository = _repository(
      session,
      MockClient((request) async {
        if (request.method == 'GET') return _ok({'id': 'user-a'});
        puts++;
        return never.future;
      }),
      timeout: const Duration(milliseconds: 20),
    );
    expect(
      _failure(await _change(repository))?.code,
      'auth.passwordOutcomeUnknown',
    );
    expect(puts, 1);
    expect(session.refreshCalls, 0);
    never.complete(_ok({'ok': true}));
  });

  test('same-account re-login invalidates a form before any request', () async {
    final session = _Session()..generation = 2;
    var calls = 0;
    final repository = _repository(
      session,
      MockClient((_) async {
        calls++;
        return _ok({'id': 'user-a'});
      }),
    );
    expect(_failure(await _change(repository))?.code, 'auth.sessionChanged');
    expect(calls, 0);
  });

  test('account switch during preflight prevents the PUT', () async {
    final session = _Session();
    final started = Completer<void>();
    final reply = Completer<http.Response>();
    final methods = <String>[];
    final repository = _repository(
      session,
      MockClient((request) {
        methods.add(request.method);
        started.complete();
        return reply.future;
      }),
    );
    final pending = _change(repository);
    await started.future;
    session.switchToB();
    reply.complete(_ok({'id': 'user-a'}));
    expect(_failure(await pending)?.code, 'auth.sessionChanged');
    expect(methods, ['GET']);
  });

  test(
    'account switch during PUT cannot replay or surface old success',
    () async {
      final session = _Session();
      final started = Completer<void>();
      final reply = Completer<http.Response>();
      final methods = <String>[];
      final repository = _repository(
        session,
        MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          started.complete();
          return reply.future;
        }),
      );
      final pending = _change(repository);
      await started.future;
      session.switchToB();
      reply.complete(_ok({'ok': true}));
      expect(_failure(await pending)?.code, 'auth.sessionChanged');
      expect(methods, ['GET', 'PUT']);
      expect(session.refreshCalls, 0);
    },
  );

  test(
    'a second screen cannot start a concurrent change; guard releases',
    () async {
      final session = _Session();
      final started = Completer<void>();
      final reply = Completer<http.Response>();
      var puts = 0;
      final repository = _repository(
        session,
        MockClient((request) async {
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          puts++;
          if (puts == 1) {
            started.complete();
            return reply.future;
          }
          return _ok({'ok': true});
        }),
      );
      final pending = _change(repository);
      await started.future;
      expect(
        _failure(await _change(repository))?.code,
        'auth.passwordInProgress',
      );
      expect(puts, 1);
      reply.complete(_ok({'ok': true}));
      expect((await pending).isRight(), isTrue);
      expect((await _change(repository)).isRight(), isTrue);
      expect(puts, 2);
    },
  );
}
