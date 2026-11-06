import 'dart:convert';

import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/category_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/category_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _Connection extends Mock implements ConnectionChecker {}

Map<String, dynamic> _row({
  String slug = 'essay-1a2b',
  String name = '随笔',
  Object? description = '短小的日常记录',
}) => {
  'id': 'tax-1',
  'kind': 'category',
  'slug': slug,
  'name': name,
  'description': description,
  'locale': 'zh-CN',
};

Map<String, dynamic> _article(String slug) => {
  'id': 'id-$slug',
  'slug': slug,
  'title': '标题 $slug',
  'summary': '摘要',
  'contentBlocksVersion': 1,
  'contentBlocks': [
    {'type': 'paragraph', 'text': '正文'},
  ],
  'publishedAt': '2026-10-01T00:00:00.000Z',
  'updatedAt': '2026-10-02T00:00:00.000Z',
  'authorId': 'u1',
  'tags': const <Object>[],
  'categories': [
    {'slug': 'essay-1a2b', 'name': '随笔'},
  ],
};

http.Response _data(Object? value, {int status = 200}) =>
    http.Response(jsonEncode({'data': value}), status);

http.Response _error(int status) =>
    http.Response('{"error":{"code":"SOMETHING"}}', status);

CategoryRemoteDataSource _remote(MockClient client, {ContentLocale? locale}) =>
    CategoryRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: client,
      contentLocale: locale,
    );

CategoryRepository _repository(MockClient client, {bool connected = true}) {
  final connection = _Connection();
  when(() => connection.isConnected).thenAnswer((_) async => connected);
  return CategoryRepositoryImpl(
    remote: _remote(client),
    connectionChecker: connection,
  );
}

void main() {
  test('the catalog is public, in the browsing language', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return _data([_row(), _row(slug: 'poetry-9z', name: '诗歌')]);
    });

    final result = await _repository(client).listCategories();
    final categories = result.getRight().toNullable();

    expect(categories, isNotNull);
    expect(categories!.map((category) => category.slug), [
      'essay-1a2b',
      'poetry-9z',
    ]);
    expect(categories.first.name, '随笔');
    expect(categories.first.description, '短小的日常记录');
    final request = seen.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/categories');
    expect(request.url.queryParameters['locale'], 'zh-CN');
    expect(request.url.queryParameters['limit'], '100');
    expect(request.url.queryParameters['offset'], '0');
    // Public read: a signed-in reader's token is never attached.
    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test('a category without a blurb is still a category', () async {
    final client = MockClient((_) async => _data([_row(description: null)]));

    final result = await _repository(client).listCategories();

    expect(result.getRight().toNullable()!.single.description, '');
  });

  test('an old deployment says "not offered", not "empty"', () async {
    for (final status in [404, 405]) {
      final result = await _repository(
        MockClient((_) async => _error(status)),
      ).listCategories();

      expect(
        result.getLeft().toNullable()?.code,
        'categories.unavailable',
        reason: '$status',
      );
    }
  });

  test('a broken catalog is a parse failure, never a shorter list', () async {
    final badPayloads = <Object?>[
      {'categories': []},
      [1, 2, 3],
      [_row(slug: '')],
      [_row(slug: ' essay-1a2b')],
      [_row(slug: '.')],
      [_row(name: '   ')],
      [_row(description: 42)],
      [_row(), _row()],
      List.generate(101, (index) => _row(slug: 'cat-$index')),
    ];
    for (final payload in badPayloads) {
      final result = await _repository(
        MockClient((_) async => _data(payload)),
      ).listCategories();

      expect(
        result.getLeft().toNullable()?.code,
        'server.parse',
        reason: '$payload',
      );
    }
  });

  test('a slug is resolved to the name the server uses', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return _data(_row());
    });

    final result = await _repository(client).getCategory('essay-1a2b');

    expect(result.getRight().toNullable(), isA<CategoryRef>());
    expect(result.getRight().toNullable()!.name, '随笔');
    expect(seen.single.url.path, '/api/v1/categories/essay-1a2b');
  });

  test('a category that is gone is an answer, not an error', () async {
    final result = await _repository(
      MockClient((_) async => _error(404)),
    ).getCategory('essay-1a2b');

    expect(result.isRight(), isTrue);
    expect(result.getRight().toNullable(), isNull);
  });

  test('a slug that cannot be addressed never reaches the network', () async {
    var calls = 0;
    final repository = _repository(
      MockClient((_) async {
        calls++;
        return _data(_row());
      }),
    );

    for (final bad in ['', '   ', ' essay-1a2b', 'essay-1a2b ', '.', '..']) {
      final missing = await repository.getCategory(bad);
      final articles = await repository.getArticlesByCategory(bad, offset: 0);
      expect(missing.getLeft().toNullable()?.code, 'client.validation');
      expect(articles.getLeft().toNullable()?.code, 'client.validation');
    }
    expect(calls, 0);
  });

  test('one page of a category carries the paging it was asked for', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return _data([_article('a1'), _article('a2')]);
    });

    final result = await _repository(
      client,
    ).getArticlesByCategory('essay-1a2b', offset: 20);
    final articles = result.getRight().toNullable();

    expect(articles, isNotNull);
    expect(articles!.map((blog) => blog.id), ['a1', 'a2']);
    final request = seen.single;
    expect(request.url.path, '/api/v1/categories/essay-1a2b/articles');
    expect(request.url.queryParameters['limit'], '20');
    expect(request.url.queryParameters['offset'], '20');
  });

  test('a slug is escaped before it becomes a path segment', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return _data(const <Object>[]);
    });

    await _repository(client).getArticlesByCategory('a/b?c#d', offset: 0);

    expect(seen.single.url.path, '/api/v1/categories/a%2Fb%3Fc%23d/articles');
  });

  test('a category removed mid-session is its own code', () async {
    final result = await _repository(
      MockClient((_) async => _error(404)),
    ).getArticlesByCategory('essay-1a2b', offset: 0);

    expect(result.getLeft().toNullable()?.code, 'category.notFound');
  });

  test('offline is reported as offline, not as an empty catalog', () async {
    final client = MockClient((_) async => _data(const <Object>[]));
    final offline = _repository(client, connected: false);

    expect(
      (await offline.listCategories()).getLeft().toNullable()?.code,
      'network.offline',
    );
    expect(
      (await offline.getArticlesByCategory(
        'essay-1a2b',
        offset: 0,
      )).getLeft().toNullable()?.code,
      'network.offline',
    );
  });
}
