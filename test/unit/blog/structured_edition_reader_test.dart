import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/datasources/nowave_structured_edition_reader.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/structured_article_fixtures.dart';

class _Auth implements NowaveViewerAuthenticator {
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 7;
  @override
  Future<bool> refresh() async => false;
}

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-uuid',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 7);

Map<String, dynamic> _article() => {
  ...structuredArticle(),
  'locale': 'en',
  'workType': 'other',
  'status': 'draft',
  'categories': [
    {'id': 'cat-id', 'name': 'Category', 'locale': 'en'},
  ],
  'tags': [
    {'id': 'tag-id', 'name': 'Tag', 'locale': 'en'},
  ],
  'author': null,
  'publishedAt': null,
  'createdAt': '2025-01-01T00:00:00Z',
  'viewCount': 0,
};

NowaveStructuredEditionReader _reader(
  _Auth auth,
  Future<http.Response> Function(http.Request) handler,
) => NowaveStructuredEditionReader(
  NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    authenticator: auth,
    httpClient: MockClient(handler),
  ),
);

StructuredEditionReadResult _decode(Object? value) =>
    decodeStructuredEditionWindow(value, key: _key);

void main() {
  group('exact authoring projection', () {
    test(
      'retains v1 block structure and all server fields without flattening',
      () {
        final original = _article();
        final result = _decode([original]);
        expect(result.status, StructuredEditionReadStatus.found);
        final edition = result.edition!;
        expect(edition.body.version, 1);
        expect(edition.body.toJsonBlocks(), original['contentBlocks']);
        expect(edition.copyRawArticle(), original);
        expect(edition.metadata.slug, 'structured');
        expect(edition.metadata.summary, 'A summary');
        expect(edition.metadata.publicationState, 'draft');
        expect(edition.metadata.categories!.values, ['cat-id']);
        expect(edition.metadata.tags!.values, ['Tag']);
        expect(edition.metadata.categories!.touched, isFalse);
        expect(edition.metadata.tags!.touched, isFalse);
        expect(edition.metadata.cover, isNull);
        expect(edition.metadataIssues, isEmpty);
      },
    );

    test('copies input deeply and never exposes mutable raw data', () {
      final original = _article();
      final edition = _decode([original]).edition!;
      final sourceBlocks = original['contentBlocks'] as List;
      (sourceBlocks.first as Map)['text'] = 'changed';
      original['title'] = 'changed';
      expect(edition.metadata.title, 'Sample title');
      expect(
        (edition.copyRawArticle()['contentBlocks'] as List).first['text'],
        'Bold代码',
      );
      expect(
        () => edition.rawArticle['title'] = 'mutated',
        throwsUnsupportedError,
      );
      final rawBlocks = edition.rawArticle['contentBlocks'] as List;
      expect(() => rawBlocks.clear(), throwsUnsupportedError);
      expect(
        () => (rawBlocks.first as Map)['text'] = 'mutated',
        throwsUnsupportedError,
      );
      final copy = edition.copyRawArticle();
      (copy['contentBlocks'] as List).clear();
      expect((edition.copyRawArticle()['contentBlocks'] as List), isNotEmpty);
    });

    test('accepts v0 without silently converting it to v1', () {
      final article = _article()
        ..['contentBlocksVersion'] = 0
        ..['contentBlocks'] = [
          {'id': 'p', 'type': 'paragraph', 'text': 'simple'},
          {
            'id': 'image',
            'type': 'image',
            'src': '/media/a',
            'alt': '',
            'caption': 'caption',
          },
        ];
      final edition = _decode([article]).edition!;
      expect(edition.body.version, 0);
      expect(edition.body.toJsonBlocks(), article['contentBlocks']);
    });

    test('explicit empty metadata remains different from missing metadata', () {
      final article = _article()
        ..['summary'] = ''
        ..['tags'] = []
        ..['categories'] = [];
      final edition = _decode([article]).edition!;
      expect(edition.metadata.summary, '');
      expect(edition.metadata.tags!.values, isEmpty);
      expect(edition.metadata.categories!.values, isEmpty);
      expect(edition.metadataIssues, isEmpty);
      article.remove('summary');
      article.remove('tags');
      article.remove('categories');
      final incomplete = _decode([article]).edition!;
      expect(incomplete.metadata.summary, isNull);
      expect(incomplete.metadata.tags, isNull);
      expect(incomplete.metadata.categories, isNull);
      expect(
        incomplete.metadataIssues,
        containsAll([
          StructuredMetadataIssue.missingSummary,
          StructuredMetadataIssue.missingTags,
          StructuredMetadataIssue.missingCategories,
        ]),
      );
    });

    test('unknown status is not inferred as published or draft', () {
      final article = _article()..['status'] = 'scheduled';
      final edition = _decode([article]).edition!;
      expect(edition.metadata.publicationState, isNull);
      expect(
        edition.metadataIssues,
        contains(StructuredMetadataIssue.unknownPublicationState),
      );
      expect(edition.copyRawArticle()['status'], 'scheduled');
    });

    test('unknown top-level fields are retained and explicitly flagged', () {
      final article = _article()
        ..['futureField'] = {
          'nested': [1, 2],
        };
      final edition = _decode([article]).edition!;
      expect(
        edition.metadataIssues,
        contains(StructuredMetadataIssue.unknownArticleFields),
      );
      expect(edition.copyRawArticle()['futureField'], {
        'nested': [1, 2],
      });
    });

    test('missing text fields remain unknown', () {
      final article = _article()
        ..remove('slug')
        ..remove('title')
        ..remove('workType')
        ..remove('status');
      final edition = _decode([article]).edition!;
      expect(edition.metadata.slug, isNull);
      expect(edition.metadata.title, isNull);
      expect(edition.metadata.workType, isNull);
      expect(edition.metadata.publicationState, isNull);
      expect(
        edition.metadataIssues,
        containsAll([
          StructuredMetadataIssue.missingSlug,
          StructuredMetadataIssue.missingTitle,
          StructuredMetadataIssue.missingWorkType,
          StructuredMetadataIssue.missingPublicationState,
        ]),
      );
    });

    test('author window missing is never a not-found conclusion', () {
      expect(_decode([]).status, StructuredEditionReadStatus.notInAuthorWindow);
      expect(
        _decode([_article()..['id'] = 'another']).status,
        StructuredEditionReadStatus.notInAuthorWindow,
      );
      expect(
        _decode(List.generate(100, (i) => {'id': 'other-$i'})).status,
        StructuredEditionReadStatus.notInAuthorWindow,
      );
    });

    test('refuses fallback and mixed editions of the requested article', () {
      final wrong = _article()..['locale'] = 'zh-CN';
      expect(
        _decode([wrong]).status,
        StructuredEditionReadStatus.editionMismatch,
      );
      expect(
        _decode([_article(), wrong]).status,
        StructuredEditionReadStatus.editionMismatch,
      );
      expect(
        _decode([wrong, _article()]).status,
        StructuredEditionReadStatus.editionMismatch,
      );
    });

    test('refuses duplicates and mismatched author', () {
      expect(
        _decode([_article(), _article()]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
      expect(
        _decode([_article()..['authorId'] = 'other']).status,
        StructuredEditionReadStatus.invalidResponse,
      );
      expect(
        _decode([_article()..remove('authorId')]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
      expect(
        _decode([_article()..remove('locale')]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
    });

    test('refuses malformed windows and malformed unrelated IDs', () {
      for (final value in [
        null,
        {},
        'error',
        [null],
        [3],
        [{}],
        [
          {'id': null},
        ],
        [
          {'id': ''},
        ],
        List.generate(101, (i) => {'id': '$i'}),
      ]) {
        expect(
          _decode(value).status,
          StructuredEditionReadStatus.invalidResponse,
          reason: '$value',
        );
      }
      expect(
        _decode([
          _article(),
          {'broken': true},
        ]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
    });

    test('refuses invalid metadata shapes and oversized values', () {
      for (final field in ['slug', 'title', 'summary', 'workType', 'status']) {
        expect(
          _decode([_article()..[field] = 4]).status,
          StructuredEditionReadStatus.invalidResponse,
          reason: field,
        );
      }
      expect(
        _decode([_article()..['title'] = 'x' * 20001]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
      expect(
        _decode([
          _article()..['tags'] = ['name'],
        ]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
      expect(
        _decode([
          _article()..['categories'] = [{}],
        ]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
      expect(
        _decode([
          _article()..['tags'] = List.generate(101, (_) => {'name': 'x'}),
        ]).status,
        StructuredEditionReadStatus.invalidResponse,
      );
    });

    test(
      'refuses unsupported blocks, versions and damaged inline structure',
      () {
        final cases = <Map<String, dynamic>>[
          _article()..['contentBlocksVersion'] = 2,
          _article()..remove('contentBlocksVersion'),
          _article()..remove('contentBlocks'),
          _article()..['contentBlocks'] = [],
          _article()
            ..['contentBlocks'] = [
              {'id': 'a', 'type': 'future', 'text': 'x'},
            ],
          _article()
            ..['contentBlocks'] = [
              {
                'id': 'a',
                'type': 'paragraph',
                'text': 'x',
                'inlines': [
                  {'text': 'y'},
                ],
              },
            ],
          _article()
            ..['contentBlocks'] = [
              {'id': 'same', 'type': 'paragraph', 'text': 'a'},
              {'id': 'same', 'type': 'paragraph', 'text': 'b'},
            ],
        ];
        for (final article in cases) {
          expect(
            _decode([article]).status,
            StructuredEditionReadStatus.unsupportedDocument,
          );
        }
      },
    );
  });

  group('HTTP boundary', () {
    test(
      'uses one authenticated exact-locale private list and no redirects',
      () async {
        final auth = _Auth();
        var count = 0;
        final reader = _reader(auth, (request) async {
          count++;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/me/articles');
          expect(request.url.queryParameters, {'locale': 'en', 'limit': '100'});
          expect(request.headers['authorization'], 'Bearer token');
          expect(request.followRedirects, isFalse);
          return http.Response(
            jsonEncode({
              'data': [_article()],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        expect(
          (await reader.read(key: _key, fence: _fence)).status,
          StructuredEditionReadStatus.found,
        );
        expect(count, 1);
      },
    );

    test('does not follow a private redirect', () async {
      var count = 0;
      final reader = _reader(_Auth(), (request) async {
        count++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://other.example/'},
        );
      });
      expect(
        (await reader.read(key: _key, fence: _fence)).status,
        StructuredEditionReadStatus.unavailable,
      );
      expect(count, 1);
    });

    test('rejects a mismatched account before making a request', () async {
      var count = 0;
      final reader = _reader(_Auth(), (_) async {
        count++;
        return http.Response('{}', 200);
      });
      final result = await reader.read(
        key: _key,
        fence: const NowaveSessionFence(userId: 'other', generation: 7),
      );
      expect(result.status, StructuredEditionReadStatus.sessionChanged);
      expect(count, 0);
    });

    test('stale generation and same-account replacement are fenced', () async {
      var count = 0;
      final auth = _Auth()..sessionGeneration = 8;
      final reader = _reader(auth, (_) async {
        count++;
        return http.Response('{}', 200);
      });
      expect(
        (await reader.read(key: _key, fence: _fence)).status,
        StructuredEditionReadStatus.sessionChanged,
      );
      expect(count, 0);
    });

    test('account change during the HTTP response discards old data', () async {
      final auth = _Auth();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final reader = _reader(auth, (_) {
        sent.complete();
        return response.future;
      });
      final result = reader.read(key: _key, fence: _fence);
      await sent.future;
      auth.activeUserId = 'other';
      auth.sessionGeneration++;
      response.complete(
        http.Response(
          jsonEncode({
            'data': [_article()],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect((await result).status, StructuredEditionReadStatus.sessionChanged);
    });

    test('network errors are distinct from an absent window entry', () async {
      for (final error in [
        const SocketException('offline'),
        TimeoutException('slow'),
        http.ClientException('closed'),
      ]) {
        final reader = _reader(_Auth(), (_) async => throw error);
        expect(
          (await reader.read(key: _key, fence: _fence)).status,
          StructuredEditionReadStatus.unavailable,
        );
      }
    });

    test('401 and 403 do not turn into empty lists', () async {
      for (final status in [401, 403]) {
        final reader = _reader(
          _Auth(),
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'DENIED', 'message': 'denied'},
            }),
            status,
          ),
        );
        expect(
          (await reader.read(key: _key, fence: _fence)).status,
          StructuredEditionReadStatus.authenticationRequired,
        );
      }
    });

    test(
      'unparseable body fails without fabricating an empty window',
      () async {
        final reader = _reader(
          _Auth(),
          (_) async => http.Response('not json', 200),
        );
        expect(
          (await reader.read(key: _key, fence: _fence)).status,
          StructuredEditionReadStatus.unavailable,
        );
      },
    );
  });
}
