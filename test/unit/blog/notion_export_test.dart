import 'dart:async';
import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/notion_export/notion_export_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator {
  @override
  String? activeUserId = 'user';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 1;
  @override
  Future<bool> refresh() async => true;
}

const _fence = NowaveSessionFence(userId: 'user', generation: 1);
Map<String, dynamic> _response() => {
  'data': {
    'bundle': {
      'version': 1,
      'database': {'id': '', 'title': 'Export'},
      'pages': [
        {
          'id': 'site:one',
          'properties': <String, dynamic>{},
          'blocks': <dynamic>[],
        },
        {
          'id': 'notion-two',
          'properties': <String, dynamic>{},
          'blocks': <dynamic>[],
        },
      ],
    },
    'report': {
      'works': [
        {
          'slug': 'hello',
          'issues': [
            {'code': 'work-type-not-carried', 'detail': 'private detail'},
          ],
          'pages': [
            {
              'locale': 'zh-CN',
              'pageId': 'site:one',
              'provenance': 'site',
              'issues': <dynamic>[],
            },
            {
              'locale': 'en',
              'pageId': 'notion-two',
              'provenance': 'notion',
              'issues': [
                {'code': 'unsupported', 'detail': 'private detail'},
              ],
            },
          ],
        },
      ],
      'missing': <dynamic>[],
      'summary': {'works': 1, 'pages': 2, 'missing': 0},
    },
  },
};
void main() {
  test(
    'requests exactly one slug and preserves bundle, sources and issue codes',
    () async {
      final auth = _Auth();
      late http.Request request;
      final response = _response();
      final repository = NotionExportRepositoryImpl(
        NowaveApiClient(
          baseUrl: Uri.parse('https://example.invalid'),
          authenticator: auth,
          httpClient: MockClient((r) async {
            request = r;
            return http.Response(jsonEncode(response), 200);
          }),
        ),
      );
      final result = (await repository.export(
        slug: 'hello',
        sessionFence: _fence,
      )).getRight().toNullable()!;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/imports/notion/export');
      expect(request.url.queryParameters, {'slugs': 'hello'});
      expect(request.headers['authorization'], 'Bearer token');
      expect(request.followRedirects, isFalse);
      expect(
        jsonDecode(result.bundleJson),
        (response['data'] as Map)['bundle'],
      );
      expect(result.issues, ['work-type-not-carried']);
      expect(result.editions.map((e) => e.fromNotion).toList(), [false, true]);
      expect(result.editions.last.issues, ['unsupported']);
    },
  );

  test(
    'missing work is not copyable and malformed or mismatched reports are rejected',
    () async {
      Map<String, dynamic> response = {
        'data': {
          'bundle': {'version': 1, 'pages': <dynamic>[]},
          'report': {
            'works': <dynamic>[],
            'missing': ['hello'],
          },
        },
      };
      var count = 0;
      final repository = NotionExportRepositoryImpl(
        NowaveApiClient(
          baseUrl: Uri.parse('https://example.invalid'),
          authenticator: _Auth(),
          httpClient: MockClient((r) async {
            count++;
            return http.Response(jsonEncode(response), 200);
          }),
        ),
      );
      final missing = (await repository.export(
        slug: 'hello',
        sessionFence: _fence,
      )).getRight().toNullable()!;
      expect(missing.missing, isTrue);
      expect(missing.bundleJson, isEmpty);
      response = _response();
      final data = response['data'] as Map;
      final report = data['report'] as Map;
      ((report['works'] as List).single['pages'] as List).first['pageId'] =
          'wrong';
      expect(
        (await repository.export(slug: 'hello', sessionFence: _fence)).isLeft(),
        isTrue,
      );
      expect(
        (await repository.export(
          slug: 'hello,other',
          sessionFence: _fence,
        )).isLeft(),
        isTrue,
      );
      expect(count, 2);
    },
  );

  test('session change during read discards the result', () async {
    final auth = _Auth();
    final pending = Completer<http.Response>();
    final repository = NotionExportRepositoryImpl(
      NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: auth,
        httpClient: MockClient((r) => pending.future),
      ),
    );
    final request = repository.export(slug: 'hello', sessionFence: _fence);
    await Future<void>.delayed(Duration.zero);
    auth.sessionGeneration++;
    pending.complete(http.Response(jsonEncode(_response()), 200));
    expect((await request).isLeft(), isTrue);
  });
}
