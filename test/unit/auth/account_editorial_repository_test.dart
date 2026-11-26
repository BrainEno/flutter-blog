import 'dart:convert';
import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/data/repositories/account_editorial_repository_impl.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The fake the shared client fences with: one account, one token, one
/// generation. `refresh` fails on purpose - this read must not come back from
/// a token renewal it never asked for.
class _Auth implements NowaveViewerAuthenticator {
  @override
  String? get accessToken => 'fake-token-a';

  @override
  String? get activeUserId => 'user-a';

  @override
  int get sessionGeneration => 1;

  @override
  Future<bool> refresh() async => false;
}

const _fence = NowaveSessionFence(userId: 'user-a', generation: 1);

AccountEditorialRepositoryImpl _repository(MockClient httpClient) {
  return AccountEditorialRepositoryImpl(
    NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: _Auth(),
      httpClient: httpClient,
    ),
  );
}

http.Response _data(Object? value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _error(int status, {String code = 'UNTRUSTED'}) => http.Response(
  jsonEncode({'error': {'code': code}}),
  status,
  headers: {'content-type': 'application/json'},
);

AccountEditorialCapacity? _capacity(
  Either<Failure, AccountEditorialCapacity> result,
) => result.fold((_) => null, (capacity) => capacity);

Failure? _failure(Either<Failure, AccountEditorialCapacity> result) =>
    result.fold((failure) => failure, (_) => null);

void main() {
  test('asks /me once, with the session token, and reads the role', () async {
    final seen = <http.Request>[];
    final repository = _repository(MockClient((request) async {
      seen.add(request);
      return _data({'id': 'user-a', 'isEditor': true});
    }));

    expect(
      _capacity(await repository.readCapacity(_fence)),
      AccountEditorialCapacity.granted,
    );
    expect(seen, hasLength(1));
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/v1/me');
    expect(seen.single.followRedirects, isFalse);
    expect(seen.single.headers['authorization'], 'Bearer fake-token-a');
  });

  test('a plain "no" is an answer, not a failure', () async {
    final repository = _repository(MockClient((_) async {
      return _data({'id': 'user-a', 'isEditor': false});
    }));

    final result = await repository.readCapacity(_fence);
    expect(_capacity(result), AccountEditorialCapacity.denied);
    expect(_failure(result), isNull);
  });

  test('a /me that omits the field is unknown, not denied', () async {
    final repository = _repository(MockClient((_) async {
      return _data({'id': 'user-a', 'email': 'a@example.invalid'});
    }));

    final result = await repository.readCapacity(_fence);
    expect(_capacity(result), AccountEditorialCapacity.unknown);
    expect(_failure(result), isNull);
  });

  test('only a JSON boolean counts as an answer', () async {
    for (final value in <Object?>['true', 1, 0, null, 'yes']) {
      var requests = 0;
      final repository = _repository(MockClient((_) async {
        requests++;
        return _data({'id': 'user-a', 'isEditor': value});
      }));

      expect(
        _capacity(await repository.readCapacity(_fence)),
        AccountEditorialCapacity.unknown,
        reason: 'isEditor: $value must not be coerced into a permission',
      );
      expect(requests, 1);
    }
  });

  test('a deployment without the endpoint says so as unknown', () async {
    for (final status in <int>[404, 405]) {
      final repository = _repository(
        MockClient((_) async => _error(status, code: 'NOT_FOUND')),
      );

      final result = await repository.readCapacity(_fence);
      expect(
        _capacity(result),
        AccountEditorialCapacity.unknown,
        reason: 'HTTP $status means this build has nothing to name',
      );
      expect(_failure(result), isNull);
    }
  });

  test('an unreadable success body is a failure, never unknown', () async {
    final repository = _repository(MockClient((_) async => _data(<Object>[])));

    final failure = _failure(await repository.readCapacity(_fence));
    expect(failure?.code, 'editorial.unanswered');
    expect(failure?.kind, FailureKind.server);
  });

  test('an expired session is reported as one', () async {
    final repository = _repository(
      MockClient((_) async => _error(401, code: 'UNAUTHENTICATED')),
    );

    final failure = _failure(await repository.readCapacity(_fence));
    expect(failure?.kind, FailureKind.auth);
    expect(failure?.code, 'auth.sessionExpired');
  });

  test('a changed account is not dressed up as an expired session', () async {
    final repository = _repository(
      MockClient((_) async => _error(401, code: 'SESSION_CHANGED')),
    );

    final failure = _failure(await repository.readCapacity(_fence));
    expect(failure?.code, isNot('auth.sessionExpired'));
  });

  test('a transport failure is a failure, not a silent unknown', () async {
    final repository = _repository(
      MockClient((_) async => throw const SocketException('offline')),
    );

    expect(
      _failure(await repository.readCapacity(_fence))?.code,
      'network.unavailable',
    );
  });

  test('a server error is not retried: one request per read', () async {
    var requests = 0;
    final repository = _repository(MockClient((_) async {
      requests++;
      return _error(500, code: 'INTERNAL');
    }));

    expect(_failure(await repository.readCapacity(_fence)), isNotNull);
    expect(requests, 1);
  });

  test('the entry rule opens for unknown and closes only on a no', () {
    expect(
      AccountEditorialCapacity.values.map(offersEditorialEntry).toList(),
      // granted, denied, unknown - the enum's own order.
      [true, false, true],
    );
  });
}
