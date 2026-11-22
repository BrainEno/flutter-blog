import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/notion_import/notion_import_repository_impl.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_plan.dart';
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
    if (!applied) 'planToken': 'payload.${'s' * 43}',
    if (!applied)
      'planExpiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String()
          .replaceFirst(RegExp(r'\.\d{6}Z$'), '.000Z'),
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
        plan: preview.getRight().toNullable()!.plan,
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
      expect(second['planToken'], 'payload.${'s' * 43}');
      expect(first.containsKey('planToken'), isFalse);
      expect(requests.every((r) => !r.followRedirects), isTrue);
    },
  );

  test(
    'selection retains source order, metadata and relations without mutation',
    () {
      final source = NotionBundle.parse(
        jsonEncode({
          'version': 1,
          'database': {'id': 'db'},
          'extra': 'keep',
          'pages': [
            {
              'id': 'a',
              'properties': {
                'Page': {
                  'type': 'title',
                  'title': [
                    {'plain_text': ' First '},
                  ],
                },
                'English': {
                  'relation': [
                    {'id': 'b'},
                  ],
                },
              },
              'blocks': [],
            },
            {'id': 'b', 'properties': {}, 'blocks': []},
            {
              'id': 'c',
              'properties': {
                'Name': {
                  'type': 'title',
                  'title': [
                    {'plain_text': 'Third'},
                  ],
                },
              },
              'blocks': [],
            },
          ],
        }),
      );
      expect(source.pageCount, 3);
      expect(source.pageTitle(0), 'First');
      expect(source.pageTitle(1), '');
      expect(source.pageTitle(2), 'Third');
      final selection = source.selectPages({2, 0});
      final pages = selection.json['pages'] as List;
      expect(pages.map((page) => page['id']).toList(), ['a', 'c']);
      expect(pages.first['properties']['English']['relation'][0]['id'], 'b');
      expect(selection.json['extra'], 'keep');
      expect(selection.json['database']['id'], 'db');
      expect(source.pageCount, 3);
      expect(() => source.selectPages({}), throwsFormatException);
      expect(() => source.selectPages({-1}), throwsFormatException);
      expect(() => source.selectPages({3}), throwsFormatException);
    },
  );

  test('valid linked editions omitted by the server are disclosed', () async {
    final auth = _Auth();
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      authenticator: auth,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(_report(false)),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final bundle = NotionBundle.parse(
      jsonEncode({
        'version': 1,
        'pages': [
          {'id': 'p', 'properties': {}, 'blocks': []},
          {'id': 'translation', 'properties': {}, 'blocks': []},
        ],
      }),
    );
    final result = await NotionImportRepositoryImpl(
      client,
    ).submit(bundle: bundle, apply: false, sessionFence: _fence);
    expect(result.getRight().toNullable()!.omittedPages, 1);
    expect(result.getRight().toNullable()!.canApply, isTrue);
  });

  test('never replays a 401 or submits under a replacement session', () async {
    final auth = _Auth();
    var calls = 0;
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      authenticator: auth,
      httpClient: MockClient((request) async {
        calls++;
        if ((jsonDecode(request.body) as Map)['apply'] == false) {
          return http.Response(jsonEncode(_report(false)), 200);
        }
        return http.Response('{}', 401);
      }),
    );
    final repository = NotionImportRepositoryImpl(client);
    final bundle = NotionBundle.parse(_json);
    final preview = await repository.submit(
      bundle: bundle,
      apply: false,
      sessionFence: _fence,
    );
    final plan = preview.getRight().toNullable()!.plan;
    expect(
      (await repository.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
        plan: plan,
      )).isLeft(),
      isTrue,
    );
    expect(calls, 2);
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
    expect(calls, 2);
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
  test(
    'plan binds immutable snapshot and identity, expires and is single-use',
    () {
      final now = DateTime.utc(2026, 1, 1);
      final bundle = NotionBundle.parse(_json);
      final other = NotionBundle.parse(_json);
      final plan = NotionImportPlan.fromPreview(
        bundle: bundle,
        fence: _fence,
        token: 'payload.${'s' * 43}',
        expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
        now: now,
      );
      expect(() => bundle.json['version'] = 2, throwsUnsupportedError);
      final pages = bundle.json['pages'] as List;
      expect(() => pages.clear(), throwsUnsupportedError);
      expect(
        () => (pages.first['properties'] as Map)['x'] = 1,
        throwsUnsupportedError,
      );
      expect(plan.usable(bundle: other, fence: _fence, now: now), isFalse);
      expect(
        plan.usable(
          bundle: bundle,
          fence: const NowaveSessionFence(userId: 'user', generation: 2),
          now: now,
        ),
        isFalse,
      );
      expect(
        plan.usable(
          bundle: bundle,
          fence: _fence,
          now: now.add(const Duration(minutes: 10)),
        ),
        isFalse,
      );
      expect(plan.consume(bundle: bundle, fence: _fence, now: now), isNotNull);
      expect(plan.consume(bundle: bundle, fence: _fence, now: now), isNull);
    },
  );

  test('legacy, malformed, oversized and expired plans fail closed', () {
    final now = DateTime.utc(2026, 1, 1);
    final bundle = NotionBundle.parse(_json);
    void check(Object? token, Object? expiry) {
      expect(
        () => NotionImportPlan.fromPreview(
          bundle: bundle,
          fence: _fence,
          token: token,
          expiresAt: expiry,
          now: now,
        ),
        throwsA(isA<NotionImportPlanFormatException>()),
      );
    }

    final expiry = now.add(const Duration(minutes: 10)).toIso8601String();
    check(null, expiry);
    check('bad', expiry);
    check('${'a' * NotionImportPlan.maxTokenBytes}.${'s' * 43}', expiry);
    check('payload.${'s' * 43}', null);
    check('payload.${'s' * 43}', now.toIso8601String());
    check('payload.${'s' * 43}', '2026-01-01T00:00:00Z');
  });

  test('missing plan and reused plan never reach the server', () async {
    var calls = 0;
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      authenticator: _Auth(),
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(
            _report((jsonDecode(request.body) as Map)['apply'] as bool),
          ),
          200,
        );
      }),
    );
    final repo = NotionImportRepositoryImpl(client);
    final bundle = NotionBundle.parse(_json);
    expect(
      (await repo.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
      )).isLeft(),
      isTrue,
    );
    expect(calls, 0);
    final report = (await repo.submit(
      bundle: bundle,
      apply: false,
      sessionFence: _fence,
    )).getRight().toNullable()!;
    expect(
      (await repo.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
        plan: report.plan,
      )).isRight(),
      isTrue,
    );
    expect(
      (await repo.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
        plan: report.plan,
      )).isLeft(),
      isTrue,
    );
    expect(calls, 2);
  });

  test('older server preview does not grant apply', () async {
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      authenticator: _Auth(),
      httpClient: MockClient((_) async {
        final response = _report(false);
        (response['data'] as Map).remove('planToken');
        return http.Response(jsonEncode(response), 200);
      }),
    );
    final result = await NotionImportRepositoryImpl(client).submit(
      bundle: NotionBundle.parse(_json),
      apply: false,
      sessionFence: _fence,
    );
    expect(result.getLeft().toNullable()!.code, 'notion.planInvalid');
  });
  test(
    'server plan rejection is mapped safely and consumes the plan',
    () async {
      var calls = 0;
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: _Auth(),
        httpClient: MockClient((request) async {
          calls++;
          final apply = (jsonDecode(request.body) as Map)['apply'] == true;
          if (!apply) return http.Response(jsonEncode(_report(false)), 200);
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'IMPORT_PLAN_INVALID',
                'message': 'private server detail',
              },
            }),
            409,
          );
        }),
      );
      final repo = NotionImportRepositoryImpl(client);
      final bundle = NotionBundle.parse(_json);
      final preview = (await repo.submit(
        bundle: bundle,
        apply: false,
        sessionFence: _fence,
      )).getRight().toNullable()!;
      final rejected = await repo.submit(
        bundle: bundle,
        apply: true,
        sessionFence: _fence,
        plan: preview.plan,
      );
      expect(rejected.getLeft().toNullable()!.code, 'notion.planInvalid');
      expect(
        rejected.getLeft().toNullable()!.message,
        isNot(contains('private')),
      );
      expect(
        (await repo.submit(
          bundle: bundle,
          apply: true,
          sessionFence: _fence,
          plan: preview.plan,
        )).isLeft(),
        isTrue,
      );
      expect(calls, 2);
    },
  );

  test('partial apply report retains each server action', () async {
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      authenticator: _Auth(),
      httpClient: MockClient((request) async {
        final apply = (jsonDecode(request.body) as Map)['apply'] as bool;
        final response = _report(apply);
        final pages = (response['data'] as Map)['pages'] as List;
        pages.add({
          ...pages.first as Map<String, dynamic>,
          'externalId': 'p2',
          'action': apply ? 'failed' : 'update',
        });
        return http.Response(jsonEncode(response), 200);
      }),
    );
    final bundle = NotionBundle.parse(
      jsonEncode({
        'version': 1,
        'pages': [
          {'id': 'p', 'properties': {}, 'blocks': []},
          {'id': 'p2', 'properties': {}, 'blocks': []},
        ],
      }),
    );
    final repo = NotionImportRepositoryImpl(client);
    final preview = (await repo.submit(
      bundle: bundle,
      apply: false,
      sessionFence: _fence,
    )).getRight().toNullable()!;
    final result = (await repo.submit(
      bundle: bundle,
      apply: true,
      sessionFence: _fence,
      plan: preview.plan,
    )).getRight().toNullable()!;
    expect(result.applied, isTrue);
    expect(result.count(NotionImportAction.create), 1);
    expect(result.count(NotionImportAction.failed), 1);
    expect(result.canApply, isFalse);
  });

  test(
    'an export image is uploaded once and known by its media address',
    () async {
      final requests = <http.Request>[];
      var status = 201;
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: _Auth(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              status == 201
                  ? {
                      'data': {
                        'id': '0b8a6f39-3a9e-4f57-9c51-1f8f7f6f2b10',
                        'src':
                            '/api/media/0b8a6f39-3a9e-4f57-9c51-1f8f7f6f2b10',
                      },
                    }
                  : {
                      'error': {
                        'code': 'BAD_USER_INPUT',
                        'message': 'Animated images are not supported.',
                      },
                    },
            ),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repository = NotionImportRepositoryImpl(client);
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
      final uploaded = await repository.uploadImage(
        bytes: bytes,
        contentType: 'image/png',
        sessionFence: _fence,
      );
      expect(
        uploaded.getRight().toNullable(),
        client.mediaUri('0b8a6f39-3a9e-4f57-9c51-1f8f7f6f2b10').toString(),
      );
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v1/me/media');
      expect(requests.single.headers['content-type'], startsWith('image/png'));
      expect(requests.single.bodyBytes, bytes);

      status = 400;
      final refused = await repository.uploadImage(
        bytes: bytes,
        contentType: 'image/png',
        sessionFence: _fence,
      );
      expect(refused.getLeft().toNullable()?.code, 'server.BAD_USER_INPUT');
      // Never retried: one request per upload.
      expect(requests, hasLength(2));
    },
  );
}
