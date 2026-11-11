import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/notion_import/notion_import_repository_impl.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
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
  int refreshes = 0;
  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }
}

const _fence = NowaveSessionFence(userId: 'user', generation: 1);
const _json =
    '{"version":1,"database":{"id":"db"},"pages":[{"id":"p","properties":{},"blocks":[]}]}';
Map<String, dynamic> _report(bool applied) => {
  'data': {
    'applied': applied,
    'pages': [
      {
        'externalId': 'p',
        'slug': 'page',
        'articleId': null,
        'title': 'Title',
        'locale': 'en',
        'action': 'create',
        'detail': 'would create',
        'issues': [
          {'code': 'warning', 'detail': 'detail'},
        ],
      },
    ],
  },
};

void main() {
  test(
    'bundle validation accepts BOM and refuses invalid or excessive input',
    () {
      expect(NotionBundle.parse('\uFEFF$_json').json['version'], 1);
      expect(() => NotionBundle.parse('[]'), throwsFormatException);
      expect(
        () => NotionBundle.parse('{"version":1,"pages":[{}]}'),
        throwsFormatException,
      );
      expect(
        () => NotionBundle.parse(
          jsonEncode({
            'version': 1,
            'pages': List.filled(201, {
              'id': 'x',
              'properties': {},
              'blocks': [],
            }),
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => NotionBundle.parse(' ' * (NotionBundle.maxRequestBytes + 1)),
        throwsFormatException,
      );
      // File size alone is insufficient: the JSON request envelope has a cost.
      final almostFull = jsonEncode({
        'version': 1,
        'pages': [],
        'padding': 'x' * (NotionBundle.maxRequestBytes - 40),
      });
      expect(() => NotionBundle.parse(almostFull), throwsFormatException);
    },
  );

  test(
    'preview and apply use the same fenced bundle and parse reports',
    () async {
      final auth = _Auth();
      final requests = <http.Request>[];
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: auth,
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(_report(body['apply'] as bool)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repository = NotionImportRepositoryImpl(client);
      final bundle = NotionBundle.parse(_json);
      final preview = await repository.submit(
        bundle: bundle,
        apply: false,
        sessionFence: _fence,
      );
      final applied = await repository.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
      );
      expect(preview.getRight().toNullable()!.canApply, isTrue);
      expect(applied.getRight().toNullable()!.canApply, isFalse);
      expect(
        preview.getRight().toNullable()!.pages.single.issues.single.code,
        'warning',
      );
      expect(requests.map((r) => r.url.path), [
        '/api/v1/imports/notion',
        '/api/v1/imports/notion',
      ]);
      final first = jsonDecode(requests.first.body) as Map<String, dynamic>;
      final second = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(first['bundle'], second['bundle']);
      expect(first['apply'], false);
      expect(second['apply'], true);
      expect(requests.every((r) => !r.followRedirects), isTrue);
    },
  );

  test('never replays a 401 or submits under a replacement session', () async {
    final auth = _Auth();
    var calls = 0;
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      authenticator: auth,
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 401);
      }),
    );
    final repository = NotionImportRepositoryImpl(client);
    final bundle = NotionBundle.parse(_json);
    expect(
      (await repository.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
      )).isLeft(),
      isTrue,
    );
    expect(calls, 1);
    expect(auth.refreshes, 0);
    auth.sessionGeneration++;
    expect(
      (await repository.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
      )).isLeft(),
      isTrue,
    );
    expect(calls, 1);
  });

  test(
    'rejects a mismatched or malformed report before offering apply',
    () async {
      final auth = _Auth();
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: auth,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(_report(true)),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final result = await NotionImportRepositoryImpl(client).submit(
        bundle: NotionBundle.parse(_json),
        apply: false,
        sessionFence: _fence,
      );
      expect(result.isLeft(), isTrue);
    },
  );
}
