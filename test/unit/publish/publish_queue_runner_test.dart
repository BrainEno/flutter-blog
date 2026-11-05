import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_publish_queue_store.dart';
import 'package:belog/features/blog/data/publish/publish_queue_runner.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements BlogRepository {}

class _MockConnectionChecker extends Mock implements ConnectionChecker {}

class _FakeIdentity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'alice';

  @override
  String? accessToken = 'token';

  @override
  int sessionGeneration = 1;

  @override
  Stream<void> get identityChanges => const Stream<void>.empty();
}

const _kCoverUrl = 'https://api.example.invalid/api/v1/media/cover-1';

const _rejected = Failure(
  '标题太长',
  kind: FailureKind.validation,
  code: 'client.validation',
);

Blog _blog(String title) => Blog(
  id: 'slug',
  title: title,
  content: 'body',
  posterId: 'alice',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2024),
);

void main() {
  late AppDatabase db;
  late Directory covers;
  late SqlitePublishQueueStore store;
  late _MockRepository repository;
  late _MockConnectionChecker connection;
  late _FakeIdentity identity;
  late PublishQueueRunner runner;

  setUpAll(() {
    registerFallbackValue(ImageUpload(bytes: Uint8List(0)));
    registerFallbackValue(
      const NowaveSessionFence(userId: 'alice', generation: 1),
    );
    registerFallbackValue(<String>[]);
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    covers = await Directory.systemTemp.createTemp('belog-runner-test');
    store = SqlitePublishQueueStore(
      db,
      apiBaseUrl: Uri.parse('https://api.example.invalid'),
      directory: covers,
    );
    repository = _MockRepository();
    connection = _MockConnectionChecker();
    identity = _FakeIdentity();
    runner = PublishQueueRunner(
      store: store,
      repository: repository,
      identity: identity,
      connectionChecker: connection,
    );
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  tearDown(() async {
    await db.close();
    if (await covers.exists()) await covers.delete(recursive: true);
  });

  Future<PublishQueueEntry> enqueue({
    String userId = 'alice',
    String title = 'Queued title',
    String key = 'key-1',
  }) => store.enqueue(
    userId: userId,
    title: title,
    content: 'body',
    tags: const ['tag'],
    idempotencyKey: key,
  );

  test('a queued entry is sent with its key and cleared', () async {
    await enqueue();
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => right(_blog('Queued title')));

    final sent = await runner.drain();

    expect(sent, 1);
    verify(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: 'Queued title',
        content: 'body',
        posterId: 'alice',
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: 'key-1',
      ),
    ).called(1);
    expect(await store.entries(userId: 'alice'), isEmpty);
  });

  test('a network failure keeps the entry for a later attempt', () async {
    await enqueue();
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => left(Failure.networkOffline()));

    final sent = await runner.drain();

    expect(sent, 0);
    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.queued);
    expect(stored.attempts, 1);
    expect(stored.nextAttemptAt, isNotNull);
    expect(stored.lastErrorCode, 'network.offline');
    // The next attempt reuses the key, so the article cannot be duplicated.
    expect(stored.idempotencyKey, 'key-1');
  });

  test('a rejected publish stops retrying and asks a human', () async {
    await enqueue();
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => left(_rejected));

    await runner.drain();

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.failed);
    expect(stored.nextAttemptAt, isNull);
  });

  test('an expired session pauses without spending attempts', () async {
    await enqueue();
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => left(Failure.auth('请重新登录')));

    await runner.drain();

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.queued);
    expect(stored.attempts, 0);
  });

  test('nothing is sent while no account is signed in', () async {
    await enqueue();
    identity.activeUserId = null;

    expect(await runner.drain(), 0);
    verifyNever(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    );
  });

  test('another account never sends someone else\'s queue', () async {
    await enqueue(userId: 'bob', title: 'bob only', key: 'key-bob');
    identity.activeUserId = 'alice';

    expect(await runner.drain(), 0);
    verifyNever(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    );
    expect((await store.entries(userId: 'bob')).single.title, 'bob only');
  });

  test('offline means no attempt is made and nothing is lost', () async {
    await enqueue();
    when(() => connection.isConnected).thenAnswer((_) async => false);

    expect(await runner.drain(), 0);
    expect((await store.entries(userId: 'alice')).single.attempts, 0);
  });

  test('entries go out oldest first, one at a time', () async {
    await enqueue(title: 'first', key: 'key-1');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await enqueue(title: 'second', key: 'key-2');
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => right(_blog('ok')));

    expect(await runner.drain(), 2);
    verifyInOrder([
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: 'first',
        content: 'body',
        posterId: 'alice',
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: 'key-1',
      ),
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: 'second',
        content: 'body',
        posterId: 'alice',
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: 'key-2',
      ),
    ]);
    expect(await store.entries(userId: 'alice'), isEmpty);
  });

  test('one drain at a time: a second call is a no-op', () async {
    await enqueue();
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return right(_blog('ok'));
    });

    final first = runner.drain();
    final second = await runner.drain();
    expect(second, 0);
    expect(await first, 1);
    verify(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).called(1);
  });

  Future<PublishQueueEntry> enqueueWithCover({String key = 'key-cover'}) {
    return store.enqueue(
      userId: 'alice',
      title: 'With cover',
      content: 'body',
      tags: const ['tag'],
      idempotencyKey: key,
      cover: ImageUpload(bytes: Uint8List.fromList(const [9, 8, 7])),
    );
  }

  test('a cover is uploaded once and reused by the retry', () async {
    await enqueueWithCover();
    when(
      () => repository.uploadCover(
        image: any(named: 'image'),
        sessionFence: any(named: 'sessionFence'),
      ),
    ).thenAnswer((_) async => right(_kCoverUrl));
    var creates = 0;
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async {
      creates++;
      // The first article request is lost; the retry must not upload again.
      return creates == 1 ? left(Failure.networkOffline()) : right(_blog('ok'));
    });

    expect(await runner.drain(), 0);
    final afterFailure = (await store.entries(userId: 'alice')).single;
    expect(afterFailure.status, PublishQueueStatus.queued);
    expect(afterFailure.coverUrl, _kCoverUrl);
    expect(afterFailure.idempotencyKey, 'key-cover');

    // Let the backoff window pass, as a later drain would.
    const rearm = 'UPDATE publish_queue SET next_attempt_at = NULL';
    await db.customStatement(rearm);
    expect(await runner.drain(), 1);

    verify(
      () => repository.uploadCover(
        image: any(named: 'image'),
        sessionFence: any(named: 'sessionFence'),
      ),
    ).called(1);
    verify(
      () => repository.uploadBlog(
        uploadedCoverUrl: _kCoverUrl,
        title: 'With cover',
        content: 'body',
        posterId: 'alice',
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: 'key-cover',
      ),
    ).called(2);
    expect(await store.entries(userId: 'alice'), isEmpty);
  });

  test('an entry that already has a cover URL is not uploaded again', () async {
    final queued = await enqueueWithCover();
    await store.recordCoverUrl(queued.id, url: _kCoverUrl);
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => right(_blog('ok')));

    expect(await runner.drain(), 1);

    verifyNever(
      () => repository.uploadCover(
        image: any(named: 'image'),
        sessionFence: any(named: 'sessionFence'),
      ),
    );
    verify(
      () => repository.uploadBlog(
        uploadedCoverUrl: _kCoverUrl,
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).called(1);
  });

  test('a failed cover upload does not publish text only', () async {
    await enqueueWithCover();
    when(
      () => repository.uploadCover(
        image: any(named: 'image'),
        sessionFence: any(named: 'sessionFence'),
      ),
    ).thenAnswer((_) async => left(Failure.networkOffline()));

    expect(await runner.drain(), 0);

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.queued);
    expect(stored.attempts, 1);
    expect(stored.coverUrl, isNull);
    verifyNever(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    );
  });

  test('a coverless entry never asks for a cover upload', () async {
    await enqueue();
    when(
      () => repository.uploadBlog(
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        posterId: any(named: 'posterId'),
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => right(_blog('ok')));

    expect(await runner.drain(), 1);

    verifyNever(
      () => repository.uploadCover(
        image: any(named: 'image'),
        sessionFence: any(named: 'sessionFence'),
      ),
    );
    verify(
      () => repository.uploadBlog(
        uploadedCoverUrl: null,
        title: 'Queued title',
        content: 'body',
        posterId: 'alice',
        tags: any(named: 'tags'),
        sessionFence: any(named: 'sessionFence'),
        idempotencyKey: 'key-1',
      ),
    ).called(1);
  });
}
