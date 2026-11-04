import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _Auth implements NowaveViewerAuthenticator {
  String user = 'A';
  String? token = 'token-A';
  int generation = 1;

  @override
  String? get activeUserId => user;
  @override
  String? get accessToken => token;
  @override
  int get sessionGeneration => generation;
  @override
  Future<bool> refresh() async => false;

  NowaveSessionFence get fence =>
      NowaveSessionFence(userId: user, generation: generation);

  void switchTo(String next) {
    user = next;
    token = 'token-$next';
    generation++;
  }
}

class _Online implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => true;
}

class _UnusedLocal extends Mock implements BlogLocalDataSource {}

NowaveApiClient _client(_Auth auth, MockClient httpClient) => NowaveApiClient(
  baseUrl: Uri.parse('https://api.example.invalid'),
  authenticator: auth,
  httpClient: httpClient,
);

BlogModel _blog({List<String> tags = const []}) => BlogModel(
  id: 'slug',
  articleId: 'article-id',
  title: 'private draft',
  content: 'private body',
  posterId: 'A',
  imageUrl: '',
  tags: tags,
  updatedAt: DateTime.utc(2025),
  serverSummary: 'summary',
  plainEditorCompatible: true,
);

http.Response _article() => http.Response(
  jsonEncode({
    'data': {
      'id': 'article-id',
      'slug': 'slug',
      'authorId': 'A',
      'title': 'title',
      'summary': 'summary',
      'contentBlocksVersion': 0,
      'contentBlocks': [
        {'id': 'block', 'type': 'paragraph', 'text': 'body'},
      ],
      'tags': [],
      'updatedAt': '2025-01-01T00:00:00.000Z',
    },
  }),
  200,
);

http.Response _tag() => http.Response(
  jsonEncode({
    'data': {'id': 'tag-id', 'name': 'topic'},
  }),
  200,
);

http.Response _asset() => http.Response(
  jsonEncode({
    'data': {'id': 'asset-id', 'contentType': 'image/webp'},
  }),
  201,
);

void main() {
  test('an old fence rejects publishing before any network call', () async {
    final auth = _Auth();
    final old = auth.fence;
    auth.switchTo('A'); // same account, a different login
    var calls = 0;
    final remote = BlogRemoteDataSourceImpl(
      _client(
        auth,
        MockClient((_) async {
          calls++;
          return _article();
        }),
      ),
    );
    await expectLater(
      remote.uploadBlog(_blog(), sessionFence: old),
      throwsA(isA<ServerException>()),
    );
    expect(calls, 0);
  });

  test('a new account does not join an old account tag lookup', () async {
    final auth = _Auth();
    final firstTagStarted = Completer<void>();
    final firstTagResponse = Completer<http.Response>();
    final calls = <String>[];
    final remote = BlogRemoteDataSourceImpl(
      _client(
        auth,
        MockClient((request) {
          final token = request.headers['authorization'];
          calls.add('${request.url.path}:$token');
          if (request.url.path.endsWith('/tags') && token == 'Bearer token-A') {
            firstTagStarted.complete();
            return firstTagResponse.future;
          }
          if (request.url.path.endsWith('/tags')) return Future.value(_tag());
          return Future.value(_article());
        }),
      ),
    );
    final first = remote.uploadBlog(
      _blog(tags: ['topic']),
      sessionFence: auth.fence,
    );
    final firstExpectation = expectLater(
      first,
      throwsA(isA<ServerException>()),
    );
    await firstTagStarted.future;
    auth.switchTo('B');
    final second = remote.uploadBlog(
      _blog(tags: ['topic']),
      sessionFence: auth.fence,
    );
    expect((await second).id, 'slug');
    firstTagResponse.complete(_tag());
    await firstExpectation;
    expect(calls, [
      '/api/v1/tags:Bearer token-A',
      '/api/v1/tags:Bearer token-B',
      '/api/v1/articles:Bearer token-B',
    ]);
  });

  test(
    'a session switch during media upload prevents the later article request',
    () async {
      final image = ImageUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      final auth = _Auth();
      final mediaStarted = Completer<void>();
      final mediaResponse = Completer<http.Response>();
      final calls = <String>[];
      final remote = BlogRemoteDataSourceImpl(
        _client(
          auth,
          MockClient((request) {
            calls.add(
              '${request.url.path}:${request.headers['authorization']}',
            );
            mediaStarted.complete();
            return mediaResponse.future;
          }),
        ),
      );
      final repository = BlogRepositoryImpl(remote, _UnusedLocal(), _Online());
      final pending = repository.uploadBlog(
        image: image,
        title: 'A',
        content: 'private',
        posterId: 'A',
        tags: [],
        sessionFence: auth.fence,
      );
      await mediaStarted.future;
      auth.switchTo('B');
      mediaResponse.complete(_asset());
      expect((await pending).isLeft(), isTrue);
      expect(calls, ['/api/v1/me/media:Bearer token-A']);
    },
  );

  test(
    'a switch during update fetch cannot send a cover or PUT under B',
    () async {
      final auth = _Auth();
      final fetchStarted = Completer<void>();
      final fetchResponse = Completer<http.Response>();
      final calls = <String>[];
      final remote = BlogRemoteDataSourceImpl(
        _client(
          auth,
          MockClient((request) {
            calls.add(
              '${request.method}:${request.url.path}:${request.headers['authorization']}',
            );
            fetchStarted.complete();
            return fetchResponse.future;
          }),
        ),
      );
      final repository = BlogRepositoryImpl(remote, _UnusedLocal(), _Online());
      final pending = repository.editBlog(
        blogId: 'slug',
        title: 'A',
        content: 'private',
        tags: [],
        image: null,
        sessionFence: auth.fence,
      );
      await fetchStarted.future;
      auth.switchTo('B');
      fetchResponse.complete(_article());
      expect((await pending).isLeft(), isTrue);
      expect(calls, ['GET:/api/v1/articles/slug:Bearer token-A']);
    },
  );

  test(
    'a sent article response is not attributed to the replacement session',
    () async {
      final auth = _Auth();
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final calls = <String>[];
      final remote = BlogRemoteDataSourceImpl(
        _client(
          auth,
          MockClient((request) {
            calls.add(
              '${request.url.path}:${request.headers['authorization']}',
            );
            started.complete();
            return response.future;
          }),
        ),
      );
      final pending = remote.uploadBlog(_blog(), sessionFence: auth.fence);
      final expectation = expectLater(pending, throwsA(isA<ServerException>()));
      await started.future;
      auth.switchTo('B');
      // A real server might already have committed this request. The client
      // rejects its response and does not silently replay it with B's token.
      response.complete(_article());
      await expectation;
      expect(calls, ['/api/v1/articles:Bearer token-A']);
    },
  );
}
