import 'dart:async';
import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `/me`-scoped routes answer for the token holder. Without a fence, a page
/// rendered for account A can show - or delete - while account B is signed in
/// (#104).
class _MemoryStore implements NowaveSessionStore {
  NowaveSessionData? stored;

  @override
  Future<void> clear() async => stored = null;

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async => stored = session;
}

NowaveTokenPair _tokens(String id) => NowaveTokenPair(
  accessToken: 'access-$id',
  refreshToken: 'refresh-$id',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

http.Response _json(Object data, [int status = 200]) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late _MemoryStore store;
  late NowaveSessionManager manager;
  late List<String> requests;

  BlogRemoteDataSource sourceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: manager,
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return handler(request);
      }),
    );
    return BlogRemoteDataSourceImpl(client, identity: manager);
  }

  Future<void> signInAs(String id) async {
    await manager.adoptSession(_tokens(id), email: '$id@example.invalid');
    await manager.updateUserId(id);
  }

  setUp(() {
    store = _MemoryStore();
    requests = <String>[];
    manager = NowaveSessionManager(
      client: NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
      ),
      store: store,
    );
  });

  test('liked articles are refused for a viewer who is not active', () async {
    await signInAs('A');
    final source = sourceFor((_) async => _json(const <dynamic>[]));

    await expectLater(
      source.getUserLikedBlogs('B'),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionChanged',
        ),
      ),
    );
    expect(requests, isEmpty, reason: 'no request may be sent for B');
  });

  test('liked articles of the active viewer load', () async {
    await signInAs('A');
    final source = sourceFor((_) async => _json(const <dynamic>[]));

    expect(await source.getUserLikedBlogs('A'), isEmpty);
    expect(requests, ['GET /api/v1/me/liked-articles']);
  });

  test('the recycle bin is bound to the active account', () async {
    await signInAs('A');
    final source = sourceFor((_) async => _json(const <dynamic>[]));

    expect(await source.getDeletedBlogs(), isEmpty);
    expect(requests, ['GET /api/v1/me/articles/deleted']);
  });

  test('a signed-out recycle bin request is refused, not sent', () async {
    final source = sourceFor((_) async => _json(const <dynamic>[]));

    await expectLater(
      source.getDeletedBlogs(),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'server.UNAUTHENTICATED',
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('a switch during the recycle-bin read is reported', () async {
    await signInAs('A');
    final readStarted = Completer<void>();
    final release = Completer<void>();
    final source = sourceFor((_) async {
      readStarted.complete();
      await release.future;
      return _json(const <dynamic>[]);
    });

    final pending = source.getDeletedBlogs();
    await readStarted.future;
    await signInAs('B');
    release.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionChanged',
        ),
      ),
    );
  });

  test('a switch during the delete is reported, not retried', () async {
    await signInAs('A');
    final deleteStarted = Completer<void>();
    final release = Completer<void>();
    final source = sourceFor((_) async {
      deleteStarted.complete();
      await release.future;
      return _json({'id': 'a1', 'deletedAt': '2025-01-01T00:00:00.000Z'});
    });

    final pending = source.deleteArticle('a1');
    await deleteStarted.future;
    await signInAs('B');
    release.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionChanged',
        ),
      ),
    );
    expect(requests, ['DELETE /api/v1/articles/a1']);
  });

  test('a like started by another account is refused', () async {
    await signInAs('A');
    final source = sourceFor(
      (_) async => _json({'likedByViewer': false}),
    );

    await expectLater(
      source.toggleLikeBlog('B', 'x'),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionChanged',
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('like state is read for the active viewer only', () async {
    await signInAs('A');
    final source = sourceFor((_) async => _json({'likedByViewer': true}));

    expect(await source.isBlogLikedByUser('A', 'x'), isTrue);
    expect(requests, ['GET /api/v1/articles/x/like']);
  });

  test('a switch during the like write is reported', () async {
    await signInAs('A');
    var likeReads = 0;
    final writeStarted = Completer<void>();
    final release = Completer<void>();
    final source = sourceFor((request) async {
      if (request.method == 'GET') {
        likeReads += 1;
        return _json({'likedByViewer': false});
      }
      writeStarted.complete();
      await release.future;
      return _json({'likedByViewer': true});
    });

    final pending = source.toggleLikeBlog('A', 'x');
    await writeStarted.future;
    await signInAs('B');
    release.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'auth.sessionChanged',
        ),
      ),
    );
    expect(likeReads, 1, reason: '读数只来自 A 的那一次');
    expect(requests.last, 'PUT /api/v1/articles/x/like');
  });

  test('restore follows the active account', () async {
    await signInAs('A');
    final source = sourceFor(
      (_) async => _json({'articleId': 'x', 'slug': 's', 'title': 't'}),
    );

    await source.restoreArticle('x');

    expect(requests, ['POST /api/v1/articles/x/restore']);
  });
}
