import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_publication_outbox.dart';
import 'package:belog/features/blog/data/publication_outbox.dart';
import 'package:belog/features/blog/domain/entities/queued_publication.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemorySession implements NowaveSessionStore {
  NowaveSessionData? value;
  @override
  Future<NowaveSessionData?> read() async => value;
  @override
  Future<void> write(NowaveSessionData session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Connection implements ConnectionChecker {
  bool connected = true;
  @override
  Future<bool> get isConnected async => connected;
}

NowaveSessionData _session(String id) => NowaveSessionData(
  userId: id,
  email: '$id@example.invalid',
  accessToken: '$id-token',
  refreshToken: '$id-refresh',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

NowaveTokenPair _pair(String id) => NowaveTokenPair(
  accessToken: '$id-token',
  refreshToken: '$id-refresh',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
  updatedAt: DateTime.utc(2026),
);
http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'data': data}), 200);

class _Fixture {
  _Fixture({
    required this.db,
    required this.store,
    required this.outbox,
    required this.sessions,
    required this.user,
    required this.connection,
    required this.clock,
  });
  final AppDatabase db;
  final SqlitePublicationOutbox store;
  final PublicationOutbox outbox;
  final NowaveSessionManager sessions;
  final AppUserCubit user;
  final _Connection connection;
  final List<DateTime> clock;

  Future<QueuedPublication> enqueue({
    String owner = 'alice',
    List<String> tags = const [],
    bool cover = false,
  }) => store.enqueue(
    ownerId: owner,
    title: 'Article',
    content: 'Body',
    tags: tags,
    coverBytes: cover ? Uint8List.fromList([1, 2, 3]) : null,
    coverMime: cover ? 'image/png' : null,
  );

  Future<void> switchTo(String id) async {
    await sessions.adoptSession(_pair(id), email: '$id@example.invalid');
    await sessions.updateUserId(id);
    user.updateUser(_user(id));
  }

  Future<void> close() async {
    outbox.dispose();
    await user.close();
    await db.close();
  }
}

Future<_Fixture> _fixture(
  Future<http.Response> Function(http.Request) handler,
) async {
  final httpClient = MockClient(handler);
  final base = Uri.parse('https://api.example.invalid');
  final storage = _MemorySession()..value = _session('alice');
  final manager = NowaveSessionManager(
    client: NowaveApiClient(baseUrl: base, httpClient: httpClient),
    store: storage,
  );
  await manager.restore();
  final api = NowaveApiClient(
    baseUrl: base,
    authenticator: manager,
    httpClient: httpClient,
  );
  final user = AppUserCubit()..updateUser(_user('alice'));
  final db = AppDatabase(NativeDatabase.memory());
  final clock = [DateTime.utc(2026, 10, 1)];
  final store = SqlitePublicationOutbox(db, now: () => clock.single);
  final connection = _Connection();
  final outbox = PublicationOutbox(
    store: store,
    client: api,
    sessions: manager,
    appUser: user,
    connection: connection,
    now: () => clock.single,
  );
  return _Fixture(
    db: db,
    store: store,
    outbox: outbox,
    sessions: manager,
    user: user,
    connection: connection,
    clock: clock,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offline intent waits; reconnect confirms exactly one publication',
    () async {
      final requests = <http.Request>[];
      final f = await _fixture((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/me')) return _ok({'id': 'alice'});
        if (request.url.path.endsWith('/articles')) {
          final body = jsonDecode(request.body) as Map;
          return _ok({'slug': body['slug'], 'authorId': 'alice'});
        }
        throw StateError('unexpected request ${request.url.path}');
      });
      addTearDown(f.close);
      final item = await f.enqueue();
      f.connection.connected = false;
      await f.outbox.processNow();
      expect(requests, isEmpty);
      expect(
        (await f.store.get('alice', item.id))?.status,
        PublicationStatus.queued,
      );
      f.connection.connected = true;
      await f.outbox.processNow();
      await f.outbox.processNow();
      final posts = requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(1));
      expect(posts.single.headers['authorization'], 'Bearer alice-token');
      expect(
        posts.single.headers['idempotency-key'],
        'belog-publication-${item.id}',
      );
      expect(
        (jsonDecode(posts.single.body) as Map)['slug'],
        'belog-${item.id}',
      );
      expect(
        (await f.store.get('alice', item.id))?.status,
        PublicationStatus.published,
      );
    },
  );

  test(
    'ambiguous POST is never resent and may be reconciled by exact owner and content',
    () async {
      Map<String, dynamic>? saved;
      var posts = 0;
      final f = await _fixture((request) async {
        if (request.url.path.endsWith('/me')) return _ok({'id': 'alice'});
        if (request.method == 'POST' &&
            request.url.path.endsWith('/articles')) {
          posts++;
          saved = (jsonDecode(request.body) as Map).cast<String, dynamic>();
          throw const SocketException('response lost after commit');
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/articles/')) {
          return _ok({...saved!, 'authorId': 'alice', 'tags': []});
        }
        throw StateError('unexpected request');
      });
      addTearDown(f.close);
      final item = await f.enqueue();
      await f.outbox.processNow();
      final failed = (await f.store.get('alice', item.id))!;
      expect(failed.articleOutcomeUncertain, isTrue);
      expect(failed.status, PublicationStatus.failed);
      expect(jsonDecode(failed.requestJson!), saved);
      expect(await f.outbox.retry('alice', item.id), isFalse);
      await f.outbox.processNow();
      expect(posts, 1);
      expect(await f.outbox.reconcile('alice', item.id), isTrue);
      expect(
        (await f.store.get('alice', item.id))?.status,
        PublicationStatus.published,
      );
      expect(posts, 1);
    },
  );

  test(
    '404 or mismatched article is not treated as confirmation or retried',
    () async {
      var posts = 0;
      final f = await _fixture((request) async {
        if (request.url.path.endsWith('/me')) return _ok({'id': 'alice'});
        if (request.method == 'POST') {
          posts++;
          throw const SocketException('unknown');
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'not found'},
          }),
          404,
        );
      });
      addTearDown(f.close);
      final item = await f.enqueue();
      await f.outbox.processNow();
      expect(await f.outbox.reconcile('alice', item.id), isFalse);
      expect(
        (await f.store.get('alice', item.id))?.articleOutcomeUncertain,
        isTrue,
      );
      expect(posts, 1);
    },
  );

  test(
    'cached owner is insufficient when the token resolves to a different actor',
    () async {
      var writes = 0;
      final f = await _fixture((request) async {
        if (request.url.path.endsWith('/me')) return _ok({'id': 'bob'});
        writes++;
        return _ok({});
      });
      addTearDown(f.close);
      final item = await f.enqueue();
      await f.outbox.processNow();
      expect(writes, 0);
      expect(
        (await f.store.get('alice', item.id))?.lastErrorCode,
        'auth.ownerUnavailable',
      );
    },
  );

  test('account switch during identity verification sends no write', () async {
    final started = Completer<void>();
    final me = Completer<http.Response>();
    final writes = <http.Request>[];
    final f = await _fixture((request) {
      if (request.url.path.endsWith('/me')) {
        started.complete();
        return me.future;
      }
      writes.add(request);
      return Future.value(_ok({}));
    });
    addTearDown(f.close);
    final item = await f.enqueue(tags: ['tag']);
    final processing = f.outbox.processNow();
    await started.future;
    await f.switchTo('bob');
    me.complete(_ok({'id': 'alice'}));
    await processing;
    expect(writes, isEmpty);
    expect(
      (await f.store.get('alice', item.id))?.lastErrorCode,
      'auth.ownerUnavailable',
    );
    expect(await f.outbox.list('alice'), isEmpty);
  });

  test(
    'verified media uses old captured token and never posts article as new account',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      final f = await _fixture((request) {
        requests.add(request);
        if (request.url.path.endsWith('/me')) {
          return Future.value(_ok({'id': 'alice'}));
        }
        if (request.url.path.endsWith('/me/media')) {
          started.complete();
          return response.future;
        }
        return Future.value(_ok({}));
      });
      addTearDown(f.close);
      final item = await f.enqueue(cover: true);
      final processing = f.outbox.processNow();
      await started.future;
      await f.switchTo('bob');
      response.complete(_ok({'id': 'asset-a', 'contentType': 'image/webp'}));
      await processing;
      final media = requests.singleWhere(
        (r) => r.url.path.endsWith('/me/media'),
      );
      expect(media.headers['authorization'], 'Bearer alice-token');
      expect(requests.where((r) => r.url.path.endsWith('/articles')), isEmpty);
      final paused = (await f.store.get('alice', item.id))!;
      expect(paused.phase, PublicationPhase.mediaReady);
      expect(paused.remoteCoverUrl, contains('asset-a'));
      expect(paused.status, PublicationStatus.failed);
    },
  );

  test(
    'a 401 after switching accounts is not refreshed and resent as the new user',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final writes = <http.Request>[];
      final f = await _fixture((request) {
        if (request.url.path.endsWith('/me')) {
          return Future.value(_ok({'id': 'alice'}));
        }
        writes.add(request);
        started.complete();
        return response.future;
      });
      addTearDown(f.close);
      final item = await f.enqueue(tags: ['tag']);
      final processing = f.outbox.processNow();
      await started.future;
      await f.switchTo('bob');
      response.complete(
        http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHENTICATED', 'message': 'expired'},
          }),
          401,
        ),
      );
      await processing;
      expect(writes, hasLength(1));
      expect(writes.single.headers['authorization'], 'Bearer alice-token');
      expect(
        (await f.store.get('alice', item.id))?.status,
        PublicationStatus.failed,
      );
    },
  );

  test(
    'an ambiguous media upload is paused, including on later passes',
    () async {
      var mediaPosts = 0;
      final f = await _fixture((request) async {
        if (request.url.path.endsWith('/me')) return _ok({'id': 'alice'});
        if (request.url.path.endsWith('/me/media')) {
          mediaPosts++;
          throw const SocketException('response lost');
        }
        throw StateError('unexpected request');
      });
      addTearDown(f.close);
      final item = await f.enqueue(cover: true);
      await f.outbox.processNow();
      await f.outbox.processNow();
      expect(mediaPosts, 1);
      expect(
        (await f.store.get('alice', item.id))?.phase,
        PublicationPhase.mediaUncertain,
      );
      expect(await f.outbox.retry('alice', item.id), isFalse);
    },
  );

  test(
    'safe pre-article errors back off and stop after a bounded number of attempts',
    () async {
      var tagPosts = 0;
      final f = await _fixture((request) async {
        if (request.url.path.endsWith('/me')) return _ok({'id': 'alice'});
        tagPosts++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'UNAVAILABLE', 'message': 'down'},
          }),
          503,
        );
      });
      addTearDown(f.close);
      final item = await f.enqueue(tags: ['tag']);
      await f.outbox.processNow();
      await f.outbox.processNow();
      expect(tagPosts, 1);
      f.clock[0] = f.clock.single.add(const Duration(seconds: 11));
      await f.outbox.processNow();
      expect(tagPosts, 2);
      f.clock[0] = f.clock.single.add(const Duration(seconds: 61));
      await f.outbox.processNow();
      await f.outbox.processNow();
      expect(tagPosts, 3);
      final failed = (await f.store.get('alice', item.id))!;
      expect(failed.status, PublicationStatus.failed);
      expect(failed.attemptCount, 3);
      expect(failed.nextAttemptAt, isNull);
    },
  );
}
