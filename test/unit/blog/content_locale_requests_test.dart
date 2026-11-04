import 'dart:convert';

import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _articleMap() => <String, dynamic>{
  'id': '00000000-0000-4000-8000-000000000001',
  'slug': 'yu-zhou',
  'title': '标题',
  'summary': '摘要',
  'authorId': 'u1',
  'contentBlocksVersion': 0,
  'contentBlocks': <Map<String, dynamic>>[
    <String, dynamic>{'id': 'b1', 'type': 'paragraph', 'text': '正文'},
  ],
  'tags': <Map<String, dynamic>>[
    <String, dynamic>{'id': 't1', 'name': '诗歌', 'slug': 'shi-ge'},
  ],
  'author': <String, dynamic>{'displayName': '作者'},
  'publishedAt': '2025-01-01T00:00:00.000Z',
  'updatedAt': '2025-01-01T00:00:00.000Z',
};

NowaveApiClient _client(http.Client inner) => NowaveApiClient(
  baseUrl: Uri.parse('https://api.example.invalid'),
  httpClient: inner,
);

void main() {
  test('article requests carry the current content language', () async {
    final requested = <Uri>[];
    final client = _client(
      MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          jsonEncode({
            'data': [_articleMap()],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final content = ContentLocale();
    final dataSource = BlogRemoteDataSourceImpl(client, contentLocale: content);

    await dataSource.getAllBlogs(page: 1);
    expect(requested.last.queryParameters['locale'], 'zh-CN');

    content.update(ContentLanguage.en);
    await dataSource.getAllBlogs(page: 1);
    expect(requested.last.queryParameters['locale'], 'en');
  });

  test('comments are requested in the same language as the articles', () async {
    final requested = <Uri>[];
    final client = _client(
      MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          jsonEncode({'data': <dynamic>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final content = ContentLocale()..update(ContentLanguage.en);
    final dataSource = CommentRemoteDataSourceImpl(
      client,
      contentLocale: content,
    );

    await dataSource.getComments('yu-zhou');
    expect(requested.last.queryParameters['locale'], 'en');
  });

  test(
    'a data source without a holder keeps the historical Chinese default',
    () async {
      final requested = <Uri>[];
      final client = _client(
        MockClient((request) async {
          requested.add(request.url);
          return http.Response(
          jsonEncode({'data': <dynamic>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
        }),
      );

      await CommentRemoteDataSourceImpl(client).getComments('yu-zhou');
      expect(requested.last.queryParameters['locale'], 'zh-CN');
    },
  );
}
