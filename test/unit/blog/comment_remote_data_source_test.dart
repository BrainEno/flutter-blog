import 'package:belog/core/error/exceptions.dart';
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
    'createdAt': '2025-06-01T00:00:00.000Z',
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

        final comments = await dataSource.getComments(_kSlug);

        expect(comments, hasLength(2));
        expect(comments.first.id, 'c1');
        expect(comments.first.authorName, '评论者-u1');
        expect(comments.first.authorAvatarUrl, contains('u1'));
        expect(comments.first.replies, hasLength(1));
        expect(comments.first.replies.first.parentCommentId, 'c1');
        expect(comments.first.replies.first.content, '同感');
        verify(
          () => client.getJson(
            '/articles/$_kSlug/comments',
            query: {'locale': 'zh-CN', 'limit': '50'},
          ),
        ).called(1);
      },
    );

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
