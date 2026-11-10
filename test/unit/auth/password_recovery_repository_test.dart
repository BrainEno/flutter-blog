import 'dart:convert';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/data/repositories/password_recovery_repository_impl.dart';
import 'package:belog/features/auth/domain/password_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_aBcD0';
const _password = '  a secure reset phrase  ';

class _Connection implements ConnectionChecker {
  _Connection(this.connected);
  final bool connected;

  @override
  Future<bool> get isConnected async => connected;
}

class _Authenticator implements NowaveAuthenticator {
  int refreshCalls = 0;

  @override
  String? get accessToken => 'current-session-token';

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    return true;
  }
}

http.Response _ok(Object? data, {int status = 200}) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _error(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': 'private server detail'},
  }),
  status,
  headers: const {'content-type': 'application/json'},
);

PasswordRecoveryRepositoryImpl _repository(
  MockClient httpClient, {
  _Connection? connection,
  _Authenticator? authenticator,
}) => PasswordRecoveryRepositoryImpl(
  client: NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: authenticator ?? _Authenticator(),
    httpClient: httpClient,
  ),
  connectionChecker: connection ?? _Connection(true),
);

Failure? _failure(Either<Failure, void> result) =>
    result.fold<Failure?>((failure) => failure, (_) => null);

void main() {
  group('reset token parsing', () {
    test('accepts the bare token and a complete mail link', () {
      expect(isPasswordResetToken(_token), isTrue);
      expect(extractPasswordResetToken(_token), _token);
      expect(
        extractPasswordResetToken(
          'Reset your password: https://site.example/reset-password?token=$_token',
        ),
        _token,
      );
      expect(extractPasswordResetToken('token=$_token'), _token);
    });

    test('refuses malformed, partial, or unrelated text', () {
      expect(isPasswordResetToken('$_token!'), isFalse);
      // A 43-character base64url string with nonzero unused tail bits is not
      // the canonical encoding accepted by the API's tokenInput helper.
      expect(isPasswordResetToken('${_token.substring(0, 42)}1'), isFalse);
      expect(extractPasswordResetToken('token=${_token.substring(1)}'), isNull);
      expect(
        extractPasswordResetToken('https://site.example/reset-password'),
        isNull,
      );
      expect(extractPasswordResetToken(''), isNull);
    });
  });

  test(
    'forgot-password is anonymous, exact, and accepts the generic 202',
    () async {
      final requests = <http.Request>[];
      final authenticator = _Authenticator();
      final repository = _repository(
        MockClient((request) async {
          requests.add(request);
          return _ok({'ok': true}, status: 202);
        }),
        authenticator: authenticator,
      );

      final result = await repository.requestPasswordReset(
        email: '  Alice@Example.invalid  ',
      );

      expect(result.isRight(), isTrue);
      expect(requests, hasLength(1));
      expect(authenticator.refreshCalls, 0);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/forgot-password');
      expect(request.headers['content-type'], contains('application/json'));
      expect(request.headers['authorization'], isNull);
      expect(request.followRedirects, isFalse);
      expect(jsonDecode(request.body), {'email': 'alice@example.invalid'});
    },
  );

  test('invalid email and offline status send no request', () async {
    var calls = 0;
    final repository = _repository(
      MockClient((_) async {
        calls++;
        return _ok({'ok': true}, status: 202);
      }),
      connection: _Connection(false),
    );

    final invalid = await repository.requestPasswordReset(email: 'bad');
    expect(_failure(invalid)?.code, 'auth.passwordRecoveryInvalidEmail');

    final offline = await repository.requestPasswordReset(
      email: 'reader@example.invalid',
    );
    expect(_failure(offline)?.code, 'network.offline');
    expect(calls, 0);
  });

  test(
    'MAIL_DISABLED is a permanent unavailable answer, not success',
    () async {
      final repository = _repository(
        MockClient((_) async => _error(409, 'MAIL_DISABLED')),
      );

      final failure = _failure(
        await repository.requestPasswordReset(email: 'reader@example.invalid'),
      );

      expect(failure?.code, 'auth.passwordRecoveryMailDisabled');
      expect(failure?.cause, isNull);
      expect(failure.toString(), isNot(contains('private server detail')));
    },
  );

  test('an unknown recovery result is not automatically replayed', () async {
    var calls = 0;
    final repository = _repository(
      MockClient((_) async {
        calls++;
        return _error(503, 'SERVICE_UNAVAILABLE');
      }),
    );

    final failure = _failure(
      await repository.requestPasswordReset(email: 'reader@example.invalid'),
    );

    expect(failure?.code, 'auth.passwordRecoveryRequestOutcomeUnknown');
    expect(failure?.cause, isNull);
    expect(calls, 1);
  });

  test(
    'reset extracts the token and sends the exact password anonymously once',
    () async {
      final requests = <http.Request>[];
      final authenticator = _Authenticator();
      final repository = _repository(
        MockClient((request) async {
          requests.add(request);
          return _ok({'ok': true});
        }),
        authenticator: authenticator,
      );

      final result = await repository.resetPassword(
        token: 'https://site.example/reset-password?token=$_token',
        password: _password,
      );

      expect(result.isRight(), isTrue);
      expect(requests, hasLength(1));
      expect(authenticator.refreshCalls, 0);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/reset-password');
      expect(request.headers['authorization'], isNull);
      expect(request.followRedirects, isFalse);
      expect(jsonDecode(request.body), {
        'token': _token,
        'password': _password,
      });
    },
  );

  test('malformed token and weak password never reach the server', () async {
    var calls = 0;
    final repository = _repository(
      MockClient((_) async {
        calls++;
        return _ok({'ok': true});
      }),
    );

    final malformed = await repository.resetPassword(
      token: 'not a reset link',
      password: _password,
    );
    expect(_failure(malformed)?.code, 'auth.passwordRecoveryTokenMalformed');

    final weak = await repository.resetPassword(
      token: _token,
      password: 'short',
    );
    expect(_failure(weak)?.code, 'auth.passwordRecoveryInvalidInput');
    expect(calls, 0);
  });

  test('401 does not reveal which part of a reset link was rejected', () async {
    final authenticator = _Authenticator();
    var calls = 0;
    final repository = _repository(
      MockClient((_) async {
        calls++;
        return _error(401, 'UNAUTHENTICATED');
      }),
      authenticator: authenticator,
    );

    final failure = _failure(
      await repository.resetPassword(token: _token, password: _password),
    );

    expect(failure?.code, 'auth.passwordRecoveryTokenRejected');
    expect(failure?.cause, isNull);
    expect(calls, 1);
    expect(authenticator.refreshCalls, 0);
  });

  test(
    'a lost reset result is not retried and requires a fresh decision',
    () async {
      var calls = 0;
      final repository = _repository(
        MockClient((_) async {
          calls++;
          return _error(503, 'SERVICE_UNAVAILABLE');
        }),
      );

      final failure = _failure(
        await repository.resetPassword(token: _token, password: _password),
      );

      expect(failure?.code, 'auth.passwordRecoveryResetOutcomeUnknown');
      expect(failure?.cause, isNull);
      expect(calls, 1);
    },
  );
}
