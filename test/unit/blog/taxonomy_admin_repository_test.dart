import 'dart:convert';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/repositories/taxonomy_admin_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/entities/taxonomy_draft.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/repositories/taxonomy_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator {
  _Auth({this.user = 'user-a'});

  String? user;

  @override
  String? get accessToken => 'fake-token-a';

  @override
  String? get activeUserId => user;

  @override
  int get sessionGeneration => 1;

  @override
  Future<bool> refresh() async => false;
}

class _Net implements ConnectionChecker {
  _Net(this.online);

  final bool online;

  @override
  Future<bool> get isConnected async => online;
}

/// The reader's own path, counted so "this screen reads what readers read"
/// stays a testable claim rather than a comment.
class _Catalogue implements CategoryRepository {
  _Catalogue({this.entries = const [], this.failed = false});

  final List<CategoryRef> entries;
  final bool failed;
  int calls = 0;

  @override
  Future<Either<Failure, List<CategoryRef>>> listCategories() {
    calls++;
    if (failed) {
      return Future.value(
        left(const Failure('读不出来', code: 'categories.unavailable')),
      );
    }
    return Future.value(right(entries));
  }

  @override
  Future<Either<Failure, CategoryRef?>> getCategory(String slug) {
    return Future.value(left(const Failure('this screen reads one row never')));
  }

  @override
  Future<Either<Failure, List<Blog>>> getArticlesByCategory(
    String slug, {
    required int offset,
  }) {
    return Future.value(left(const Failure('this screen lists nothing')));
  }
}

const _fence = NowaveSessionFence(userId: 'user-a', generation: 1);
const _id = '11111111-1111-4111-8111-111111111111';
const _draft = TaxonomyDraft(
  name: '声音与噪音',
  slug: 'noise-2a3b',
  description: '不和谐的编辑选择',
);

TaxonomyAdminRepositoryImpl _repository(
  MockClient httpClient, {
  _Auth? auth,
  bool online = true,
  CategoryRepository? categories,
}) {
  final client = NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: auth ?? _Auth(),
    httpClient: httpClient,
  );
  return TaxonomyAdminRepositoryImpl(
    categories: categories ?? _Catalogue(),
    client: client,
    connectionChecker: _Net(online),
  );
}

Future<Either<Failure, TaxonomyWrite>> _create(
  TaxonomyAdminRepository repository, {
  TaxonomyDraft? draft,
}) {
  return repository.create(fence: _fence, draft: draft ?? _draft);
}

Future<Either<Failure, TaxonomyWrite>> _remove(
  TaxonomyAdminRepository repository, {
  String id = _id,
}) {
  return repository.remove(fence: _fence, id: id);
}

TaxonomyWrite? _wrote(Either<Failure, TaxonomyWrite> result) {
  return result.fold((_) => null, (outcome) => outcome);
}

Failure? _failed(Either<Failure, TaxonomyWrite> result) {
  return result.fold((failure) => failure, (_) => null);
}

Map<String, dynamic> _bodyOf(http.Request request) {
  return jsonDecode(request.body) as Map<String, dynamic>;
}

http.Response _row({Object? id = _id}) {
  final data = <String, Object?>{
    'id': id,
    'kind': 'category',
    'slug': 'noise-2a3b',
    'name': '声音与噪音',
    'description': '不和谐的编辑选择',
    'locale': 'zh-CN',
  };
  return http.Response(
    jsonEncode({'data': data}),
    201,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _receipt(bool deleted) {
  return http.Response(
    jsonEncode({
      'data': {'deleted': deleted},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _raw(String body, [int status = 200]) {
  return http.Response(
    body,
    status,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _error(int status, {String code = 'UNTRUSTED'}) {
  return http.Response(
    jsonEncode({
      'error': {'code': code},
    }),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  test('a create sends the four keys and nothing else', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      MockClient((request) async {
        seen.add(request);
        return _row();
      }),
    );

    expect(_wrote(await _create(repository)), TaxonomyWrite.done);
    expect(seen, hasLength(1));
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/v1/taxonomies');
    // The set of keys is part of the contract: one key outside the route's list
    // is a 400 for the whole body, so an added convenience field would turn a
    // catalogue question into a request error.
    expect(_bodyOf(seen.single).keys.toSet(), {
      'kind',
      'slug',
      'name',
      'description',
    });
    expect(_bodyOf(seen.single)['kind'], 'category');
    expect(_bodyOf(seen.single)['slug'], 'noise-2a3b');
    // `locale` is the server's own constant today; repeating it here would pin
    // the app to that answer, and omitting it lets the deployment decide.
    expect(_bodyOf(seen.single).containsKey('locale'), isFalse);
  });

  test('a draft this app cannot read back never reaches the network', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _row();
      }),
    );

    final blank = await _create(
      repository,
      draft: const TaxonomyDraft(name: '   ', slug: 'x-1'),
    );
    expect(_failed(blank)?.code, 'taxonomy.nameBlank');

    final dot = await _create(
      repository,
      draft: const TaxonomyDraft(name: '噪音', slug: '..'),
    );
    expect(_failed(dot)?.code, 'taxonomy.slugUnreadable');

    final padded = await _create(
      repository,
      draft: const TaxonomyDraft(name: '噪音', slug: ' noise-2a3b '),
    );
    expect(_failed(padded)?.code, 'taxonomy.slugUnreadable');
    expect(requests, 0);
  });

  test('the description cap is the server cap, not a smaller one', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      MockClient((request) async {
        seen.add(request);
        return _row();
      }),
    );
    final atTheCap = '字' * kTaxonomyDescriptionLimit;
    final oneOver = '$atTheCap多';

    final tooLong = await _create(
      repository,
      draft: TaxonomyDraft(name: '噪音', slug: 'x-1', description: oneOver),
    );
    expect(_failed(tooLong)?.code, 'taxonomy.descriptionTooLong');
    expect(_failed(tooLong)?.kind, FailureKind.validation);
    expect(seen, isEmpty);

    await _create(
      repository,
      draft: TaxonomyDraft(name: '噪音', slug: 'x-1', description: atTheCap),
    );
    expect(seen, hasLength(1));
    expect(_bodyOf(seen.single)['description'], atTheCap);
  });

  test('offline is stated without spending a request', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _row();
      }),
      online: false,
    );

    expect(_failed(await _create(repository))?.code, 'network.offline');
    expect(_failed(await _remove(repository))?.code, 'network.offline');
    expect(requests, 0);
  });

  test('a 201 the app cannot read is unknown, and never resent', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _raw('{"data": null}');
      }),
    );

    expect(_wrote(await _create(repository)), TaxonomyWrite.unknown);
    // A second attempt would duplicate a category that may well have landed,
    // and this API has no conditional write to make retrying safe.
    expect(requests, 1);
  });

  test('a stored row that cannot name itself is not a confirmation', () async {
    final repository = _repository(
      MockClient((_) async => _row(id: null)),
    );

    expect(_wrote(await _create(repository)), TaxonomyWrite.unknown);
  });

  test('403, 404 and 405 answer about the deployment', () async {
    final refused = await _create(
      _repository(MockClient((_) async => _error(403, code: 'FORBIDDEN'))),
    );
    final gone = await _create(
      _repository(MockClient((_) async => _error(404, code: 'NOT_FOUND'))),
    );
    final unsupported = await _create(
      _repository(MockClient((_) async => _error(405))),
    );

    expect(_wrote(refused), TaxonomyWrite.refused);
    expect(_wrote(gone), TaxonomyWrite.unavailable);
    expect(_wrote(unsupported), TaxonomyWrite.unavailable);
  });

  test('a duplicate keeps the existing classification', () async {
    final repository = _repository(
      MockClient((_) async => _error(409, code: 'CONFLICT')),
    );

    final failure = _failed(await _create(repository));
    expect(failure?.code, 'server.CONFLICT');
    expect(failure?.kind, FailureKind.validation);
  });

  test('a 400 is reported as a failure, not as a row that is gone', () async {
    final repository = _repository(
      MockClient((_) async => _error(400, code: 'BAD_USER_INPUT')),
    );

    final failure = _failed(await _create(repository));
    expect(failure?.code, 'server.BAD_USER_INPUT');
    expect(_wrote(await _create(repository)), isNull);
  });

  test('a changed account stops the write before it is sent', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _row();
      }),
      auth: _Auth(user: 'user-b'),
    );

    final failure = _failed(await _create(repository));
    expect(failure?.code, 'auth.sessionChanged');
    expect(failure?.kind, FailureKind.auth);
    expect(requests, 0);
  });

  test('a delete addresses the row the catalogue carried', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      MockClient((request) async {
        seen.add(request);
        return _receipt(true);
      }),
    );

    expect(_wrote(await _remove(repository)), TaxonomyWrite.done);
    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/api/v1/taxonomies/$_id');
  });

  test('only an explicit true says the row is gone', () async {
    final notYours = await _remove(
      _repository(MockClient((_) async => _receipt(false))),
    );
    final bare = await _remove(
      _repository(MockClient((_) async => _raw('{"data": true}'))),
    );
    final unreadable = await _remove(
      _repository(MockClient((_) async => _raw('{"data": "yes"}'))),
    );

    // `deleted: false` covers "not yours to delete" and "no such row" alike, so
    // the app stops at "not removed" and invents no reason.
    expect(_wrote(notYours), TaxonomyWrite.notRemoved);
    // A bare boolean is how another deletion route answers. Reading it as a
    // receipt here would claim a removal this route never confirmed.
    expect(_wrote(bare), TaxonomyWrite.unknown);
    expect(_wrote(unreadable), TaxonomyWrite.unknown);
  });

  test('a row without an id cannot be deleted, and nothing is sent', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _receipt(true);
      }),
    );

    expect(
      _failed(await _remove(repository, id: ''))?.code,
      'taxonomy.idUnknown',
    );
    expect(
      _failed(await _remove(repository, id: '   '))?.code,
      'taxonomy.idUnknown',
    );
    expect(requests, 0);
  });

  test('a delete on a route that is not there says so', () async {
    final gone = await _remove(
      _repository(MockClient((_) async => _error(404, code: 'NOT_FOUND'))),
    );
    final refused = await _remove(
      _repository(MockClient((_) async => _error(403, code: 'FORBIDDEN'))),
    );

    expect(_wrote(gone), TaxonomyWrite.unavailable);
    expect(_wrote(refused), TaxonomyWrite.refused);
  });

  test('the catalogue is read through the reader path, once', () async {
    final categories = _Catalogue(
      entries: const [
        CategoryRef(id: _id, slug: 'noise-2a3b', name: '噪音'),
      ],
    );
    final repository = _repository(
      MockClient((_) async => _raw('{}')),
      categories: categories,
    );

    final result = await repository.catalogue();
    expect(categories.calls, 1);
    expect(result.getOrElse(() => const []), hasLength(1));
  });

  test('a failed catalogue read is forwarded, not emptied', () async {
    final repository = _repository(
      MockClient((_) async => _raw('{}')),
      categories: _Catalogue(failed: true),
    );

    final result = await repository.catalogue();
    final code = result.fold((failure) => failure.code, (_) => null);
    expect(code, 'categories.unavailable');
  });
}
