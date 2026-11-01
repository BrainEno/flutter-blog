import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/latest_feed_cursor.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Map<String, dynamic> _row(int n, String time) => {
  'id': _uuid(n),
  'slug': 'article-$n',
  'title': 'title $n',
  'authorId': 'author',
  'contentBlocksVersion': 0,
  'contentBlocks': [
    {'id': 'p1', 'type': 'paragraph', 'text': 'body'},
  ],
  'publishedAt': time,
  'updatedAt': time,
};

http.Response _ok(Object data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

BlogRemoteDataSourceImpl _dataSource(MockClient httpClient) =>
    BlogRemoteDataSourceImpl(
      NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        httpClient: httpClient,
      ),
    );

void main() {
  const time = '2026-11-01T12:34:56.123Z';

  test('first page stays compatible with offset-only servers', () async {
    final seen = <Uri>[];
    final dataSource = _dataSource(
      MockClient((request) async {
        seen.add(request.url);
        return _ok([_row(1, time)]);
      }),
    );
    final page = await dataSource.getAllBlogs(page: 1);
    expect(page.single.publishedAt, time);
    expect(seen.single.path, '/api/v1/articles');
    expect(seen.single.queryParameters, {
      'limit': '10',
      'offset': '0',
      'locale': 'zh-CN',
    });
  });

  test('cursor request uses an overlap window, never offset', () async {
    final seen = <Uri>[];
    final firstRows = List.generate(10, (index) => _row(index, time));
    final first = firstRows.map(BlogModel.fromNowaveArticle).toList();
    final cursor = LatestFeedContinuation.tryStart(first)!;
    final dataSource = _dataSource(
      MockClient((request) async {
        seen.add(request.url);
        return _ok([
          ...firstRows,
          ...List.generate(10, (index) => _row(index + 10, time)),
        ]);
      }),
    );

    final slice = await dataSource.getAllBlogsAfter(cursor: cursor.token);
    expect(slice.blogs.map((blog) => blog.id), [
      for (var n = 10; n < 20; n++) 'article-$n',
    ]);
    expect(
      LatestFeedContinuation.tryDecode(slice.nextCursor!)!.seenIds,
      hasLength(20),
    );
    expect(seen.single.path, '/api/v1/articles');
    expect(seen.single.queryParameters, {
      'limit': '20',
      'cursor': cursor.apiCursor,
      'locale': 'zh-CN',
    });
    expect(seen.single.queryParameters.containsKey('offset'), isFalse);
  });

  test('a legacy server silently ignoring cursor is not accepted', () async {
    final first = [
      BlogModel.fromNowaveArticle(_row(1, '2026-11-01T12:34:57.000Z')),
      BlogModel.fromNowaveArticle(_row(2, time)),
    ];
    final cursor = LatestFeedContinuation.tryStart(first)!;
    final dataSource = _dataSource(
      MockClient(
        (_) async => _ok([_row(1, '2026-11-01T12:34:57.000Z'), _row(2, time)]),
      ),
    );
    await expectLater(
      dataSource.getAllBlogsAfter(cursor: cursor.token),
      throwsA(isA<LatestFeedCursorUnavailable>()),
    );
  });

  test(
    'bad-input cursor rejection is distinguished from server/rate errors',
    () async {
      final first = [BlogModel.fromNowaveArticle(_row(1, time))];
      final cursor = LatestFeedContinuation.tryStart(first)!;
      for (final status in [400, 429, 500]) {
        final code = switch (status) {
          400 => 'BAD_USER_INPUT',
          429 => 'RATE_LIMITED',
          _ => 'INTERNAL_SERVER_ERROR',
        };
        final dataSource = _dataSource(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {'code': code, 'message': 'fixture'},
              }),
              status,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        await expectLater(
          dataSource.getAllBlogsAfter(cursor: cursor.token),
          throwsA(
            status == 400
                ? isA<LatestFeedCursorUnavailable>()
                : isA<ServerException>().having(
                    (e) => e.code,
                    'code',
                    status == 429 ? 'server.RATE_LIMITED' : 'server.error',
                  ),
          ),
        );
      }
    },
  );

  test('malformed rows do not become an empty successful page', () async {
    final cursor = LatestFeedContinuation.tryStart([
      BlogModel.fromNowaveArticle(_row(1, time)),
    ])!;
    final dataSource = _dataSource(MockClient((_) async => _ok([42])));
    await expectLater(
      dataSource.getAllBlogsAfter(cursor: cursor.token),
      throwsA(isA<LatestFeedCursorUnavailable>()),
    );
  });
}
