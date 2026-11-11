import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNowaveApiClient extends Mock implements NowaveApiClient {}

const _kSlug = 'my-slug';

/// A comment row as the server serializes it (plain-text content v0 with
/// the joined author profile and nested replies).
Map<String, dynamic> _commentMap({
  String id = 'c1',
  String? parentId,
  String authorId = 'u1',
  String content = '写得真好',
  String createdAt = '2025-06-01T00:00:00.000Z',
  List<Map<String, dynamic>> replies = const [],
}) {
  return <String, dynamic>{
    'id': id,
    'articleId': 'server-uuid-1',
    'authorId': authorId,
    'parentCommentId': parentId,
    'content': content,
    'contentBlocks': null,
    'contentBlocksVersion': 0,
    'createdAt': createdAt,
    'updatedAt': '2025-06-01T00:00:00.000Z',
    'locale': 'zh-CN',
    'replies': replies,
    'author': <String, dynamic>{
      'id': authorId,
      'displayName': '评论者-$authorId',
      'avatarUrl': 'https://img.example.invalid/$authorId.png',
    },
  };
}

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

void main() {
  late MockNowaveApiClient client;
  late CommentRemoteDataSourceImpl dataSource;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = MockNowaveApiClient();
    dataSource = CommentRemoteDataSourceImpl(client);
  });

  group('getComments', () {
    test(
      'maps the thread tree with nested replies and author fields',
      () async {
        when(
          () => client.getJson(any(), query: any(named: 'query')),
        ).thenAnswer(
          (_) async => [
            _commentMap(
              id: 'c1',
              replies: [
                _commentMap(
                  id: 'c2',
                  parentId: 'c1',
                  authorId: 'u2',
                  content: '同感',
                ),
              ],
            ),
            _commentMap(id: 'c3', authorId: 'u3'),
          ],
        );

        final page = await dataSource.getComments(_kSlug);

        expect(page.items, hasLength(2));
        expect(page.nextCursor, isNull);
        expect(page.items.first.id, 'c1');
        expect(page.items.first.authorName, '评论者-u1');
        expect(page.items.first.authorAvatarUrl, contains('u1'));
        expect(page.items.first.replies, hasLength(1));
        expect(page.items.first.replies.first.parentCommentId, 'c1');
        expect(page.items.first.replies.first.content, '同感');
        verify(
          () => client.getJson(
            '/articles/$_kSlug/comments',
            query: {'locale': 'zh-CN', 'limit': '50'},
          ),
        ).called(1);
      },
    );

    test(
      'maps edit timestamps, including nested replies and legacy or malformed values',
      () async {
        final validRoot = _commentMap(
          id: 'edited-root',
          replies: [
            _commentMap(id: 'edited-child', parentId: 'edited-root')
              ..['editedAt'] = '2026-11-11T09:05:00.000Z',
          ],
        )..['editedAt'] = '2026-11-10T12:00:00.000Z';
        final legacy = _commentMap(id: 'legacy');
        final nullValue = _commentMap(id: 'null')..['editedAt'] = null;
        final invalid = _commentMap(id: 'invalid')..['editedAt'] = 'not-a-date';
        final wrongType = _commentMap(id: 'wrong-type')..['editedAt'] = 17;
        when(
          () => client.getJson(any(), query: any(named: 'query')),
        ).thenAnswer(
          (_) async => [validRoot, legacy, nullValue, invalid, wrongType],
        );
        final page = await dataSource.getComments(_kSlug);
        expect(page.items[0].editedAt, DateTime.utc(2026, 11, 10, 12));
        expect(
          page.items[0].replies.single.editedAt,
          DateTime.utc(2026, 11, 11, 9, 5),
        );
        expect(page.items[0].createdAt, DateTime.utc(2025, 6, 1));
        expect(
          page.items.skip(1).map((comment) => comment.editedAt),
          everyElement(isNull),
        );
        expect(page.items[0].replies.single.parentCommentId, 'edited-root');
      },
    );

    test(
      'builds the cursor from the exact timestamp of the last root',
      () async {
        const timestamp = '2026-06-01T00:00:00.123Z';
        const replyTimestamp = '2026-06-01T00:00:00.456Z';
        final rows = List<Map<String, dynamic>>.generate(
          49,
          (index) => _commentMap(
            id: _uuid(index + 1),
            createdAt: '2026-05-31T00:00:00.000Z',
          ),
        );
        final lastRootId = _uuid(50);
        rows.add(
          _commentMap(
            id: lastRootId,
            createdAt: timestamp,
            replies: [
              _commentMap(
                id: _uuid(51),
                parentId: lastRootId,
                createdAt: replyTimestamp,
              ),
            ],
          ),
        );
        when(
          () => client.getJson(any(), query: any(named: 'query')),
        ).thenAnswer((_) async => rows);

        final page = await dataSource.getComments(_kSlug);
        final expected = base64Url
            .encode(utf8.encode('$timestamp|$lastRootId'))
            .replaceAll('=', '');

        expect(page.items, hasLength(50));
        expect(page.nextCursor, expected);
        expect(page.nextCursor!.contains('='), isFalse);
      },
    );

    test('sends the continuation cursor unchanged', () async {
      const cursor = 'dGltZXN0YW1wfHV1aWQ';
      when(
        () => client.getJson(any(), query: any(named: 'query')),
      ).thenAnswer((_) async => <dynamic>[]);

      final page = await dataSource.getComments(_kSlug, cursor: cursor);

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      verify(
        () => client.getJson(
          '/articles/$_kSlug/comments',
          query: {'locale': 'zh-CN', 'limit': '50', 'cursor': cursor},
        ),
      ).called(1);
    });

    test('a cursor-only 400 is reported as unavailable pagination', () async {
      when(() => client.getJson(any(), query: any(named: 'query'))).thenThrow(
        NowaveApiException(
          statusCode: 400,
          code: 'BAD_USER_INPUT',
          message: 'Invalid comment cursor.',
        ),
      );

      expect(
        () => dataSource.getComments(_kSlug, cursor: 'valid-looking-cursor'),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'code',
            'comments.cursorUnavailable',
          ),
        ),
      );
    });

    test('a malformed boundary on a full page is a parse failure', () async {
      final rows = List<Map<String, dynamic>>.generate(
        50,
        (index) => _commentMap(id: _uuid(index + 1)),
      );
      rows.last['createdAt'] = '2026-06-01T00:00:00Z';
      when(
        () => client.getJson(any(), query: any(named: 'query')),
      ).thenAnswer((_) async => rows);

      expect(
        () => dataSource.getComments(_kSlug),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'code',
            'client.parse',
          ),
        ),
      );
    });

    test('an API error surfaces as a ServerException', () async {
      when(() => client.getJson(any(), query: any(named: 'query'))).thenThrow(
        NowaveApiException(statusCode: 404, code: 'NOT_FOUND', message: 'nope'),
      );

      expect(
        () => dataSource.getComments(_kSlug),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('createComment', () {
    test('posts the v0 body with the idempotency header', () async {
      when(
        () => client.postJson(
          any(),
          any(),
          query: any(named: 'query'),
          extraHeaders: any(named: 'extraHeaders'),
        ),
      ).thenAnswer((_) async => _commentMap(id: 'c9', content: '新评论'));

      final comment = await dataSource.createComment(
        slug: _kSlug,
        content: '新评论',
        parentCommentId: null,
        idempotencyKey: 'key-1',
      );

      expect(comment.id, 'c9');
      expect(comment.content, '新评论');
      verify(
        () => client.postJson(
          '/articles/$_kSlug/comments',
          {'content': '新评论', 'parentCommentId': null},
          query: {'locale': 'zh-CN'},
          extraHeaders: {'Idempotency-Key': 'key-1'},
        ),
      ).called(1);
    });

    test(
      'maps the documented depth rejection from the HTTP envelope safely',
      () async {
        final requests = <http.Request>[];
        final transport = MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'COMMENT_DEPTH_EXCEEDED',
                'message': 'private backend detail',
              },
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        });
        addTearDown(transport.close);
        final realClient = NowaveApiClient(
          baseUrl: Uri.parse('https://example.invalid'),
          httpClient: transport,
        );
        final remote = CommentRemoteDataSourceImpl(realClient);
        await expectLater(
          () => remote.createComment(
            slug: _kSlug,
            content: 'draft',
            parentCommentId: 'parent',
            idempotencyKey: 'key-1',
          ),
          throwsA(
            isA<ServerException>()
                .having((e) => e.code, 'code', 'comments.depthExceeded')
                .having((e) => e.kind, 'kind', FailureKind.validation)
                .having(
                  (e) => e.message,
                  'safe message',
                  isNot(contains('private backend detail')),
                )
                .having((e) => e.cause, 'cause', isA<NowaveApiException>()),
          ),
        );
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.url.path, '/api/v1/articles/my-slug/comments');
        expect(jsonDecode(requests.single.body), {
          'content': 'draft',
          'parentCommentId': 'parent',
        });
        expect(requests.single.headers['idempotency-key'], 'key-1');
      },
    );

    for (final scenario in [
      (400, 'BAD_USER_INPUT', 'server.BAD_USER_INPUT'),
      (500, 'COMMENT_DEPTH_EXCEEDED', 'server.error'),
    ]) {
      test(
        'other status/code ${scenario.$1}/${scenario.$2} keeps generic mapping',
        () async {
          when(
            () => client.postJson(
              any(),
              any(),
              query: any(named: 'query'),
              extraHeaders: any(named: 'extraHeaders'),
            ),
          ).thenThrow(
            NowaveApiException(
              statusCode: scenario.$1,
              code: scenario.$2,
              message: 'private backend detail',
            ),
          );
          await expectLater(
            () => dataSource.createComment(
              slug: _kSlug,
              content: 'draft',
              idempotencyKey: 'key-1',
            ),
            throwsA(
              isA<ServerException>()
                  .having((e) => e.code, 'code', scenario.$3)
                  .having(
                    (e) => e.message,
                    'safe message',
                    isNot(contains('private backend detail')),
                  ),
            ),
          );
        },
      );
    }

    test('a reply carries the parent comment id', () async {
      when(
        () => client.postJson(
          any(),
          any(),
          query: any(named: 'query'),
          extraHeaders: any(named: 'extraHeaders'),
        ),
      ).thenAnswer((_) async => _commentMap(id: 'c10', parentId: 'c1'));

      await dataSource.createComment(
        slug: _kSlug,
        content: '回复',
        parentCommentId: 'c1',
        idempotencyKey: 'key-2',
      );

      verify(
        () => client.postJson(
          '/articles/$_kSlug/comments',
          {'content': '回复', 'parentCommentId': 'c1'},
          query: {'locale': 'zh-CN'},
          extraHeaders: {'Idempotency-Key': 'key-2'},
        ),
      ).called(1);
    });
  });

  group('deleteComment', () {
    test('returns true when the server reports the delete', () async {
      when(
        () => client.deleteJson(any()),
      ).thenAnswer((_) async => {'deleted': true});

      expect(await dataSource.deleteComment('c1'), isTrue);
      verify(() => client.deleteJson('/comments/c1')).called(1);
    });

    test('returns false when the comment was already gone', () async {
      when(
        () => client.deleteJson(any()),
      ).thenAnswer((_) async => {'deleted': false});

      expect(await dataSource.deleteComment('c1'), isFalse);
    });
  });
}
