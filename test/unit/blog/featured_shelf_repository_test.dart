import 'dart:convert';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/repositories/featured_shelf_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/featured_shelf_entry.dart';
import 'package:belog/features/blog/domain/repositories/featured_shelf_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator {
  _Auth({this.user = 'user-a'});

  String? user;
  int generation = 1;

  @override
  String? get accessToken => 'fake-token-a';

  @override
  String? get activeUserId => user;

  @override
  int get sessionGeneration => generation;

  @override
  Future<bool> refresh() async => false;
}

class _Net implements ConnectionChecker {
  _Net(this.online);

  final bool online;

  @override
  Future<bool> get isConnected async => online;
}

const _fence = NowaveSessionFence(userId: 'user-a', generation: 1);
const _locale = 'zh-CN';
const _firstId = '11111111-1111-4111-8111-111111111111';
const _secondId = '22222222-2222-4222-8222-222222222222';

FeaturedShelfRepositoryImpl _repository(
  MockClient httpClient, {
  _Auth? auth,
  bool online = true,
}) {
  final client = NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: auth ?? _Auth(),
    httpClient: httpClient,
  );
  return FeaturedShelfRepositoryImpl(
    client: client,
    connectionChecker: _Net(online),
  );
}

/// Every save in these tests is the same call with a different list, kept in
/// one place so a failure below names the shelf rather than the plumbing.
Future<Either<Failure, FeaturedShelfSaveResult>> _send(
  FeaturedShelfRepository repository, {
  List<String> ids = const [],
}) {
  return repository.save(fence: _fence, locale: _locale, articleIds: ids);
}

Map<String, dynamic> _row({
  String id = _firstId,
  String slug = 'poetry-1a2b',
  String title = '关于篇幅',
}) {
  return {'id': id, 'slug': slug, 'title': title, 'contentBlocksVersion': 0};
}

http.Response _list(List<Object?> rows) => http.Response(
  jsonEncode({'data': rows}),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _raw(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

http.Response _error(int status, {String code = 'UNTRUSTED'}) => http.Response(
  jsonEncode({'error': {'code': code}}),
  status,
  headers: {'content-type': 'application/json'},
);

List<FeaturedShelfEntry>? _loaded(
  Either<Failure, List<FeaturedShelfEntry>> result,
) => result.fold((_) => null, (entries) => entries);

Failure? _readFailure(Either<Failure, List<FeaturedShelfEntry>> result) =>
    result.fold((failure) => failure, (_) => null);

FeaturedShelfSaveResult? _saved(
  Either<Failure, FeaturedShelfSaveResult> result,
) => result.fold((_) => null, (outcome) => outcome);

Failure? _saveFailure(Either<Failure, FeaturedShelfSaveResult> result) =>
    result.fold((failure) => failure, (_) => null);

void main() {
  test('the shelf read asks for the whole capacity, not a feed page', () async {
    final seen = <http.Request>[];
    final rows = [_row(slug: 'first'), _row(id: _secondId, slug: 'second')];
    final client = MockClient((request) async {
      seen.add(request);
      return _list(rows);
    });
    final repository = _repository(client);

    final entries = _loaded(await repository.load(locale: _locale))!;
    expect(seen, hasLength(1));
    expect(seen.single.url.path, '/api/v1/featured');
    expect(seen.single.url.queryParameters['limit'], '20');
    expect(seen.single.url.queryParameters['locale'], _locale);
    expect(entries.map((entry) => entry.slug), ['first', 'second']);
    // A shelf saved from a truncated read would delete the missing picks.
    final ids = entries.map((entry) => entry.articleId).toList();
    expect(ids, [_firstId, _secondId]);
    expect(entries.first.title, '关于篇幅');
  });

  test('a row it cannot name fails instead of shortening the shelf', () async {
    final rows = [_row(), _row(id: 'not-a-uuid ', slug: 'loose')];
    final client = MockClient((_) async => _list(rows));
    final repository = _repository(client);

    final result = await repository.load(locale: _locale);
    final code = _readFailure(result)?.code;
    // A silently dropped row would come back as a shorter shelf on the next
    // save, deleting somebody's pick.
    expect(code, 'featured.unreadable');
  });

  test('a non-list payload is a failure, not an empty shelf', () async {
    final client = MockClient((_) async => _raw('{"data": null}'));
    final repository = _repository(client);

    final result = await repository.load(locale: _locale);
    expect(_readFailure(result)?.code, 'featured.unreadable');
  });

  test('browse omits the query when there is nothing to search', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return _list([_row()]);
    });
    final repository = _repository(client);

    await repository.browse(locale: 'en');
    await repository.browse(locale: 'en', query: '  诗  ');
    expect(seen, hasLength(2));
    expect(seen.first.url.queryParameters.containsKey('query'), isFalse);
    expect(seen.last.url.path, '/api/v1/articles');
    expect(seen.last.url.queryParameters['query'], '诗');
    expect(seen.last.url.queryParameters['locale'], 'en');
  });

  test('the save is the whole ordered list under its one key', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return _list([_row()]);
    });
    final repository = _repository(client);

    final result = await _send(repository, ids: [_firstId]);
    expect(_saved(result)!.outcome, FeaturedShelfSave.stored);
    expect(seen, hasLength(1));
    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '/api/v1/featured');
    expect(seen.single.url.queryParameters, {'locale': _locale});
    expect(seen.single.followRedirects, isFalse);
    // The server refuses a body carrying any other key.
    expect(seen.single.body, '{"articleIds":["$_firstId"]}');
  });

  test('stored ids come back as the server sent them', () async {
    final rows = [_row(id: _secondId), _row(id: _firstId)];
    final client = MockClient((_) async => _list(rows));
    final repository = _repository(client);

    final result = await _send(repository, ids: [_firstId, _secondId]);
    // A concurrent editor must be visible, not papered over.
    expect(_saved(result)!.storedIds, [_secondId, _firstId]);
  });

  test('403 is an answer about the account, not a transport failure', () async {
    final client = MockClient((_) async => _error(403, code: 'FORBIDDEN'));
    final repository = _repository(client);

    final result = await _send(repository);
    expect(_saved(result)!.outcome, FeaturedShelfSave.refused);
    expect(_saveFailure(result), isNull);
  });

  test('an old deployment says the shelf is not offered here', () async {
    for (final status in <int>[404, 405]) {
      final client = MockClient((_) async => _error(status));
      final repository = _repository(client);

      final result = await _send(repository);
      // HTTP $status means there is no editorial route on this deployment.
      expect(_saved(result)!.outcome, FeaturedShelfSave.unavailable);
    }
  });

  test('an unreadable success is unknown, never a retry', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _raw('{"data": "ok"}');
    });
    final repository = _repository(client);

    final result = await _send(repository);
    expect(_saved(result)!.outcome, FeaturedShelfSave.unknown);
    expect(requests, 1);
  });

  test('a 401 is reported once and never replayed', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _error(401, code: 'UNAUTHENTICATED');
    });
    final repository = _repository(client);

    final result = await _send(repository);
    final failure = _saveFailure(result);
    expect(failure?.kind, FailureKind.auth);
    // A replay could double-apply a whole-list write.
    expect(requests, 1);
  });

  test('a shelf from a left account is refused before the request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _list(const []);
    });
    final repository = _repository(client, auth: _Auth(user: 'user-b'));

    final failure = _saveFailure(await _send(repository));
    expect(failure?.code, 'auth.sessionChanged');
    expect(requests, 0);
  });

  test('offline is stated without spending a request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _list(const []);
    });
    final repository = _repository(client, online: false);

    final failure = _saveFailure(await _send(repository));
    expect(failure?.code, 'network.offline');
    expect(requests, 0);
  });

  test('the server ceiling is applied before sending', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _list(const []);
    });
    final repository = _repository(client);
    final twice = const ['x', 'x'];

    final tooLong = [for (var i = 0; i < 21; i++) '$i'];
    final overCapacity = _saveFailure(await _send(repository, ids: tooLong));
    expect(overCapacity?.code, 'featured.tooMany');
    final duplicated = _saveFailure(await _send(repository, ids: twice));
    expect(duplicated?.code, 'featured.duplicate');
    expect(requests, 0);
    expect(featuredShelfProblem(const ['a', 'b']), isNull);
  });
}
