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
  _Auth({this.user = 'user-a', this.generation = 1});

  String? user;
  int generation;

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

FeaturedShelfRepositoryImpl _repository(
  MockClient httpClient, {
  _Auth? auth,
  bool online = true,
}) {
  return FeaturedShelfRepositoryImpl(
    client: NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: auth ?? _Auth(),
      httpClient: httpClient,
    ),
    connectionChecker: _Net(online),
  );
}

Map<String, dynamic> _row({
  String id = '11111111-1111-4111-8111-111111111111',
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
  jsonEncode({
    'error': {'code': code},
  }),
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
    final repository = _repository(
      MockClient((request) async {
        seen.add(request);
        return _list([
          _row(slug: 'first'),
          _row(id: '22222222-2222-4222-8222-222222222222', slug: 'second'),
        ]);
      }),
    );

    final entries = _loaded(await repository.load(locale: 'zh-CN'))!;
    expect(seen, hasLength(1));
    expect(seen.single.url.path, '/api/v1/featured');
    expect(seen.single.url.queryParameters['limit'], '20');
    expect(seen.single.url.queryParameters['locale'], 'zh-CN');
    expect(entries.map((entry) => entry.slug), ['first', 'second']);
    expect(
      entries.map((entry) => entry.articleId).toList(),
      [
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
      ],
      reason: 'editorial order is the whole point of the read',
    );
    expect(entries.first.title, '关于篇幅');
  });

  test('a row it cannot name fails instead of shortening the shelf', () {
    final repository = _repository(
      MockClient((_) async {
        return _list([
          _row(),
          _row(id: 'not-a-uuid ', slug: 'loose'),
        ]);
      }),
    );

    expect(
      _readFailure(await repository.load(locale: 'zh-CN'))?.code,
      'featured.unreadable',
      reason:
          'a silently dropped row would be saved back as a shorter shelf, '
          'deleting somebody\'s pick on the next save',
    );
  });

  test('a non-list payload is a failure, not an empty shelf', () async {
    final repository = _repository(
      MockClient((_) async {
        return _raw('{"data": null}');
      }),
    );

    expect(
      _readFailure(await repository.load(locale: 'zh-CN'))?.code,
      'featured.unreadable',
    );
  });

  test('browse omits the query when there is nothing to search', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      MockClient((request) async {
        seen.add(request);
        return _list([_row()]);
      }),
    );

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
    final repository = _repository(
      MockClient((request) async {
        seen.add(request);
        return _list([_row()]);
      }),
    );

    final result = await repository.save(
      fence: _fence,
      locale: 'zh-CN',
      articleIds: ['11111111-1111-4111-8111-111111111111'],
    );

    expect(_saved(result)!.outcome, FeaturedShelfSave.stored);
    expect(seen, hasLength(1));
    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '/api/v1/featured');
    expect(seen.single.url.queryParameters, {'locale': 'zh-CN'});
    expect(seen.single.followRedirects, isFalse);
    expect(
      seen.single.body,
      '{"articleIds":["11111111-1111-4111-8111-111111111111"]}',
      reason: 'the server refuses a body with any other key',
    );
  });

  test('stored ids come back as the server sent them', () async {
    final repository = _repository(
      MockClient((_) async {
        return _list([
          _row(id: '22222222-2222-4222-8222-222222222222'),
          _row(id: '11111111-1111-4111-8111-111111111111'),
        ]);
      }),
    );

    final result = await repository.save(
      fence: _fence,
      locale: 'zh-CN',
      articleIds: [
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
      ],
    );

    expect(
      _saved(result)!.storedIds,
      [
        '22222222-2222-4222-8222-222222222222',
        '11111111-1111-4111-8111-111111111111',
      ],
      reason: 'a concurrent editor must be visible, not papered over',
    );
  });

  test('403 is an answer about the account, not a transport failure', () async {
    final repository = _repository(
      MockClient((_) async => _error(403, code: 'FORBIDDEN')),
    );

    final result = await repository.save(
      fence: _fence,
      locale: 'zh-CN',
      articleIds: const [],
    );

    expect(_saved(result)!.outcome, FeaturedShelfSave.refused);
    expect(_saveFailure(result), isNull);
  });

  test('an old deployment says the shelf is not offered here', () async {
    for (final status in <int>[404, 405]) {
      final repository = _repository(
        MockClient((_) async => _error(status, code: 'NOT_FOUND')),
      );

      final result = await repository.save(
        fence: _fence,
        locale: 'zh-CN',
        articleIds: const [],
      );
      expect(
        _saved(result)!.outcome,
        FeaturedShelfSave.unavailable,
        reason: 'HTTP $status means no editorial route here',
      );
    }
  });

  test('an unreadable success is unknown, never a retry', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _raw('{"data": "ok"}');
      }),
    );

    final result = await repository.save(
      fence: _fence,
      locale: 'zh-CN',
      articleIds: const [],
    );

    expect(_saved(result)!.outcome, FeaturedShelfSave.unknown);
    expect(requests, 1);
  });

  test('a 401 is reported once and never replayed', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _error(401, code: 'UNAUTHENTICATED');
      }),
    );

    final failure = _saveFailure(
      await repository.save(
        fence: _fence,
        locale: 'zh-CN',
        articleIds: const [],
      ),
    );

    expect(failure?.kind, FailureKind.auth);
    expect(requests, 1, reason: 'a replay could double-apply a whole-list PUT');
  });

  test('a shelf from a left account is refused before the request', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _list(const []);
      }), auth: _Auth(user: 'user-b'));

      final failure = _saveFailure(
        await repository.save(
          fence: _fence,
          locale: 'zh-CN',
          articleIds: const [],
        ),
      );

      expect(failure?.code, 'auth.sessionChanged');
      expect(requests, 0);
    });

    test('offline is stated without spending a request', () async {
      var requests = 0;
      final repository = _repository(
        MockClient((_) async {
          requests++;
          return _list(const []);
        }),
        online: false,
      );

      final failure = _saveFailure(
        await repository.save(
          fence: _fence,
          locale: 'zh-CN',
          articleIds: const [],
        ),
      );

      expect(failure?.code, 'network.offline');
      expect(requests, 0);
    });

    test('the server\'s own ceiling is applied before sending', () async {
      var requests = 0;
      final repository = _repository(
        MockClient((_) async {
          requests++;
          return _list(const []);
        }),
      );

    final tooLong = [
      for (var i = 0; i < kFeaturedShelfCapacity + 1; i++) '$i',
    ];
    expect(
      _saveFailure(
        await repository.save(
          fence: _fence,
          locale: 'zh-CN',
          articleIds: tooLong,
        ),
      )?.code,
      'featured.tooMany',
    );
    expect(
      _saveFailure(
        await repository.save(
          fence: _fence,
          locale: 'zh-CN',
          articleIds: const ['x', 'x'],
        ),
      )?.code,
      'featured.duplicate',
    );
    expect(requests, 0);
    expect(featuredShelfProblem(const ['a', 'b']), isNull);
  });
}
