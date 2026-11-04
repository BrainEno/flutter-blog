import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tag browsing is served by `GET /tags` (name -> opaque slug) and
/// `GET /tags/:slug/articles` (#106). The lookup must not assume the tag sits
/// in the first 100 rows.
late List<Uri> requests;

BlogRemoteDataSource sourceFor(
  Future<http.Response> Function(http.Request) handler,
) {
  requests = <Uri>[];
  return BlogRemoteDataSourceImpl(
    NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        return handler(request);
      }),
    ),
  );
}

http.Response _json(Object data, [int status = 200]) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

List<Map<String, dynamic>> _tags(String prefix, int count) => [
  for (var i = 0; i < count; i++)
    {
      'id': '$prefix-$i',
      'kind': 'tag',
      'name': '$prefix-$i',
      'slug': '$prefix-$i',
    },
];

Map<String, dynamic> _article(String slug) => {
  'id': 'id-$slug',
  'slug': slug,
  'title': '文章 $slug',
  'authorId': 'u1',
  'updatedAt': '2026-10-01T00:00:00.000Z',
  'tags': const <dynamic>[],
};

void main() {
  test('a tag past the first 100 rows still resolves', () async {
    final source = sourceFor((request) async {
      final offset = request.url.queryParameters['offset'];
      if (offset == '0') return _json(_tags('other', 100));
      return _json([
        {'id': 't-1', 'kind': 'tag', 'name': '夜航', 'slug': 'yehang-1a2b'},
      ]);
    });

    final tag = await source.resolveTag('夜航');

    expect(tag?.slug, 'yehang-1a2b');
    expect(tag?.name, '夜航');
    expect(requests.map((uri) => uri.queryParameters['offset']), ['0', '100']);
    expect(
      requests.every((uri) => uri.queryParameters['query'] == '夜航'),
      isTrue,
      reason: '查找必须走服务端 query，而不是翻第一页',
    );
  });

  test('a short page with no match means the tag does not exist', () async {
    final source = sourceFor((_) async => _json(_tags('other', 7)));

    expect(await source.resolveTag('夜航'), isNull);
    expect(requests, hasLength(1), reason: '短页就是尽头，不该继续翻');
  });

  test('taxonomy rows with a null name or slug are skipped', () async {
    final source = sourceFor(
      (_) async => _json([
        {'id': 'a', 'kind': 'tag', 'name': null, 'slug': 'null-name'},
        {'id': 'b', 'kind': 'tag', 'name': '夜航', 'slug': null},
        {'id': 'c', 'kind': 'tag', 'name': '夜航', 'slug': 'yehang-1a2b'},
      ]),
    );

    expect((await source.resolveTag('夜航'))?.slug, 'yehang-1a2b');
  });

  test('matching ignores case, as the server canonicalizes it', () async {
    final source = sourceFor(
      (_) async => _json([
        {'id': 't', 'kind': 'tag', 'name': 'Flutter', 'slug': 'flutter-9f'},
      ]),
    );

    expect((await source.resolveTag('  flutter '))?.slug, 'flutter-9f');
  });

  test('an empty name never reaches the network', () async {
    final source = sourceFor((_) async => _json(const <dynamic>[]));

    expect(await source.resolveTag('   '), isNull);
    expect(requests, isEmpty);
  });

  test('a page of tag articles is walked by offset', () async {
    final source = sourceFor(
      (_) async => _json([_article('a'), _article('b')]),
    );

    final articles = await source.getArticlesByTag('yehang-1a2b', offset: 20);

    expect(articles.map((blog) => blog.id), ['a', 'b']);
    expect(requests.single.path, '/api/v1/tags/yehang-1a2b/articles');
    expect(requests.single.queryParameters['offset'], '20');
    expect(
      requests.single.queryParameters['limit'],
      '$kTagPageSize',
      reason: '页大小是「还有下一页」的判断依据',
    );
  });

  test('a 404 on the tag is reported, not turned into an empty list', () async {
    final source = sourceFor(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'NOT_FOUND', 'message': 'The tag was not found.'},
        }),
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    await expectLater(
      source.getArticlesByTag('yehang-1a2b', offset: 0),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'tag.notFound',
        ),
      ),
    );
  });
}
