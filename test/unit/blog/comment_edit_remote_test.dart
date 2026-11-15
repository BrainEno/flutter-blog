import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator, NowaveProactiveAuthenticator {
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'secret';
  @override
  int sessionGeneration = 1;
  int refreshes = 0;
  int proactive = 0;
  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }

  @override
  Future<bool> ensureFreshAccess() async {
    proactive++;
    return true;
  }
}

Map<String, dynamic> _row() => {
  'id': 'c1',
  'articleId': 'work',
  'authorId': 'author',
  'parentCommentId': null,
  'content': 'corrected',
  'contentBlocksVersion': 0,
  'contentBlocks': null,
  'createdAt': '2026-01-01T00:00:00Z',
  'editedAt': '2026-02-01T00:00:00Z',
  'replies': <dynamic>[],
};

void main() {
  const fence = NowaveSessionFence(userId: 'author', generation: 1);
  test(
    'plain eligibility fails closed for rich, absent and malformed versions',
    () {
      expect(CommentModel.fromMap(_row()).isPlainText, isTrue);
      expect(
        CommentModel.fromMap(_row()..remove('contentBlocks')).isPlainText,
        isFalse,
      );
      expect(
        CommentModel.fromMap(
          _row()..remove('contentBlocksVersion'),
        ).isPlainText,
        isFalse,
      );
      expect(
        CommentModel.fromMap(
          _row()..['contentBlocksVersion'] = 0.0,
        ).isPlainText,
        isFalse,
      );
      expect(
        CommentModel.fromMap(_row()..['contentBlocksVersion'] = 1).isPlainText,
        isFalse,
      );
      expect(
        CommentModel.fromMap(_row()..['contentBlocks'] = []).isPlainText,
        isFalse,
      );
    },
  );

  test(
    'PATCH uses locale and fence without refresh, replay or redirects',
    () async {
      final requests = <http.Request>[];
      final auth = _Auth();
      final transport = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'data': _row()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(transport.close);
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: auth,
        httpClient: transport,
      );
      final remote = CommentRemoteDataSourceImpl(client);
      final value = await remote.editComment(
        commentId: 'c1',
        content: 'corrected',
        sessionFence: fence,
      );
      expect(value.content, 'corrected');
      expect(value.editedAt, DateTime.utc(2026, 2, 1));
      expect(requests, hasLength(1));
      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.path, '/api/v1/comments/c1');
      expect(requests.single.url.queryParameters, {'locale': 'zh-CN'});
      expect(jsonDecode(requests.single.body), {'content': 'corrected'});
      expect(requests.single.followRedirects, isFalse);
      expect(requests.single.headers['authorization'], 'Bearer secret');
      expect(auth.proactive, 0);
      expect(auth.refreshes, 0);
    },
  );

  for (final status in [401, 404, 405, 500, 302]) {
    test('status $status is not replayed and is classified safely', () async {
      var calls = 0;
      final auth = _Auth();
      final transport = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'private'},
          }),
          status,
          headers: {
            'content-type': 'application/json',
            if (status == 302) 'location': 'https://other.invalid/',
          },
        );
      });
      addTearDown(transport.close);
      final remote = CommentRemoteDataSourceImpl(
        NowaveApiClient(
          baseUrl: Uri.parse('https://example.invalid'),
          authenticator: auth,
          httpClient: transport,
        ),
      );
      await expectLater(
        () => remote.editComment(
          commentId: 'c1',
          content: 'corrected',
          sessionFence: fence,
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.code,
            'code',
            status == 405
                ? 'comments.editUnavailable'
                : (status >= 500 || status == 302
                      ? 'comments.editUnknown'
                      : isNot('comments.editUnavailable')),
          ),
        ),
      );
      expect(calls, 1);
      expect(auth.proactive, 0);
      expect(auth.refreshes, 0);
    });
  }

  test('invalid success response is an uncertain outcome', () async {
    final transport = MockClient(
      (_) async => http.Response(
        jsonEncode({'data': _row()..['authorId'] = 'other'}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(transport.close);
    final remote = CommentRemoteDataSourceImpl(
      NowaveApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        authenticator: _Auth(),
        httpClient: transport,
      ),
    );
    await expectLater(
      () => remote.editComment(
        commentId: 'c1',
        content: 'corrected',
        sessionFence: fence,
      ),
      throwsA(
        isA<ServerException>().having(
          (e) => e.code,
          'code',
          'comments.editUnknown',
        ),
      ),
    );
  });
}
