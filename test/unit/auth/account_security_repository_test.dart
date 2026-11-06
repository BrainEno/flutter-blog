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
  List<String>? remembered,
  Future<void> Function(String email)? rememberEmail,
}) => AccountSecurityRepositoryImpl(
  client: NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: session,
    httpClient: httpClient,
    timeout: timeout,
  ),
  session: session,
  connectionChecker: connection ?? _Connection(true),
  rememberEmail: rememberEmail ??
      (remembered == null
          ? null
          : (email) async {
              remembered.add(email);
            }),
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

Future<Either<Failure, String>> _changeEmail(
  AccountSecurityRepositoryImpl repository, {
  String userId = 'user-a',
  int generation = 1,
  String password = 'current password',
  String email = 'new@example.invalid',
}) => repository.changeEmail(
  expectedUserId: userId,
  expectedSessionGeneration: generation,
  currentPassword: password,
  newEmail: email,
);

Failure? _emailFailure(Either<Failure, String> result) =>
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
          jsonEncode({
            'data': {'ok': true},
          }),
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

  group('changeEmail', () {
    test(
      'preflights, sends the address once, and returns what was stored',
      () async {
        final session = _Session();
        final requests = <http.Request>[];
        final remembered = <String>[];
        final repository = _repository(
          session,
          MockClient((request) async {
            requests.add(request);
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            return _ok({'ok': true, 'email': 'new@example.invalid'});
          }),
          remembered: remembered,
        );

        final result = await _changeEmail(repository);

        expect(
          result.fold((_) => null, (email) => email),
          'new@example.invalid',
        );
        expect(requests.map((request) => request.method), ['GET', 'PUT']);
        expect(requests[0].url.path, '/api/v1/me');
        expect(requests[1].url.path, '/api/v1/me/email');
        expect(requests[1].headers['authorization'], 'Bearer access-a');
        expect(requests[1].followRedirects, isFalse);
        expect(jsonDecode(requests[1].body), {
          'password': 'current password',
          'email': 'new@example.invalid',
        });
        // The rest of the app must show the address, not the request.
        expect(remembered, ['new@example.invalid']);
        expect(session.refreshCalls, 0);
      },
    );

    test(
      'the server normalizes the address; the client sends it that way',
      () async {
        final requests = <http.Request>[];
        final remembered = <String>[];
        final repository = _repository(
          _Session(),
          MockClient((request) async {
            requests.add(request);
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            return _ok({'ok': true, 'email': 'new@example.invalid'});
          }),
          remembered: remembered,
        );

        await _changeEmail(repository, email: '  New@Example.INVALID  ');

        expect(jsonDecode(requests[1].body)['email'], 'new@example.invalid');
        expect(remembered, ['new@example.invalid']);
      },
    );

    test('addresses the server would refuse never leave the device', () async {
      var calls = 0;
      final repository = _repository(
        _Session(),
        MockClient((_) async {
          calls++;
          return _ok({'id': 'user-a'});
        }),
      );

      for (final email in [
        '',
        'no-at-sign',
        'a@b',
        'a..b@example.com',
        'a@b c',
      ]) {
        final failure = _emailFailure(
          await _changeEmail(repository, email: email),
        );
        expect(failure?.code, 'account.emailInvalid', reason: email);
      }
      expect(
        _emailFailure(await _changeEmail(repository, password: ''))?.code,
        'account.emailInvalid',
      );
      expect(calls, 0);
    });

    test('an address another account holds is named, not generic', () async {
      final repository = _repository(
        _Session(),
        MockClient((request) async {
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          return _error(409, 'EMAIL_TAKEN', message: 'new@example.invalid');
        }),
      );

      final failure = _emailFailure(await _changeEmail(repository));

      expect(failure?.code, 'account.emailTaken');
      expect(failure?.cause, isNull);
      expect(failure.toString(), isNot(contains('new@example.invalid')));
    });

    for (final entry in <int, String>{
      400: 'account.emailInvalid',
      401: 'account.emailRejected',
      403: 'server.permission',
      404: 'account.emailUnsupported',
      405: 'account.emailUnsupported',
      429: 'auth.rateLimited',
      500: 'account.emailOutcomeUnknown',
      503: 'account.emailOutcomeUnknown',
    }.entries) {
      test(
        'email endpoint status ${entry.key} is safely classified',
        () async {
          final session = _Session();
          var puts = 0;
          final repository = _repository(
            session,
            MockClient((request) async {
              if (request.method == 'GET') return _ok({'id': 'user-a'});
              puts++;
              return _error(entry.key, 'UNTRUSTED');
            }),
          );
          AppLogger.clearDiagnostics();

          final failure = _emailFailure(await _changeEmail(repository));

          expect(failure?.code, entry.value);
          expect(failure?.cause, isNull);
          expect(
            failure.toString(),
            isNot(contains('current password')),
          );
          expect(
            AppLogger.diagnosticsReport(),
            isNot(contains('current password')),
          );
          expect(puts, 1);
          expect(session.refreshCalls, 0);
        },
      );
    }

    test('an unreadable 2xx is an unknown outcome, never a success', () async {
      for (final response in [
        http.Response('not json', 200),
        _ok({'ok': false}),
        _ok([1, 2, 3]),
      ]) {
        final remembered = <String>[];
        final repository = _repository(
          _Session(),
          MockClient((request) async {
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            return response;
          }),
          remembered: remembered,
        );

        final failure = _emailFailure(await _changeEmail(repository));

        expect(failure?.code, 'account.emailOutcomeUnknown');
        expect(remembered, isEmpty);
      }
    });

    test('a dropped connection after the PUT is uncertain', () async {
      final repository = _repository(
        _Session(),
        MockClient((request) async {
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          throw const SocketException('fixture transport error');
        }),
      );

      expect(
        _emailFailure(await _changeEmail(repository))?.code,
        'account.emailOutcomeUnknown',
      );
    });

    test(
      'a changed address is still reported when the local note fails',
      () async {
        final repository = _repository(
          _Session(),
          MockClient((request) async {
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            return _ok({'ok': true, 'email': 'new@example.invalid'});
          }),
          rememberEmail: (_) async => throw StateError('storage unavailable'),
        );

        final result = await _changeEmail(repository);

        expect(
          result.fold((_) => null, (email) => email),
          'new@example.invalid',
        );
      },
    );

    test(
      'an address the server stored but did not echo is not a failure',
      () async {
        final remembered = <String>[];
        final repository = _repository(
          _Session(),
          MockClient((request) async {
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            return _ok({'ok': true});
          }),
          remembered: remembered,
        );

        final result = await _changeEmail(repository);

        expect(
          result.fold((_) => null, (email) => email),
          'new@example.invalid',
        );
        expect(remembered, ['new@example.invalid']);
      },
    );

    test('offline and a changed account never send the password', () async {
      final connection = _Connection(false);
      var calls = 0;
      final repository = _repository(
        _Session(),
        MockClient((_) async {
          calls++;
          return _ok({'id': 'user-a'});
        }),
        connection: connection,
      );

      expect(
        _emailFailure(await _changeEmail(repository))?.code,
        'network.offline',
      );
      expect(calls, 0);

      connection.connected = true;
      expect(
        _emailFailure(await _changeEmail(repository, generation: 9))?.code,
        'auth.sessionChanged',
      );
      expect(calls, 0);
    });

    test(
      'a switch during the PUT drops the result and records nothing',
      () async {
        final session = _Session();
        final started = Completer<void>();
        final reply = Completer<http.Response>();
        final remembered = <String>[];
        final repository = _repository(
          session,
          MockClient((request) async {
            if (request.method == 'GET') return _ok({'id': 'user-a'});
            started.complete();
            return reply.future;
          }),
          remembered: remembered,
        );

        final pending = _changeEmail(repository);
        await started.future;
        session.switchToB();
        reply.complete(_ok({'ok': true, 'email': 'new@example.invalid'}));

        expect(_emailFailure(await pending)?.code, 'auth.sessionChanged');
        expect(remembered, isEmpty);
      },
    );

    test('the password guard also covers e-mail changes', () async {
      final started = Completer<void>();
      final reply = Completer<http.Response>();
      var puts = 0;
      final repository = _repository(
        _Session(),
        MockClient((request) async {
          if (request.method == 'GET') return _ok({'id': 'user-a'});
          puts++;
          if (puts == 1) {
            started.complete();
            return reply.future;
          }
          return _ok({'ok': true, 'email': 'new@example.invalid'});
        }),
      );

      final pendingPassword = _change(repository);
      await started.future;

      expect(
        _emailFailure(await _changeEmail(repository))?.code,
        'account.changeInProgress',
      );
      expect(puts, 1);

      reply.complete(_ok({'ok': true}));
      expect((await pendingPassword).isRight(), isTrue);
      expect(
        (await _changeEmail(repository)).fold((_) => null, (email) => email),
        'new@example.invalid',
      );
    });
  });
}
