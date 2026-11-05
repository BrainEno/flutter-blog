import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_publish_queue_store.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _firstBackend = Uri.parse('https://first.example.invalid/api-root/');
final _secondBackend = Uri.parse('https://second.example.invalid/api-root');

void main() {
  late AppDatabase db;
  late Directory covers;
  late SqlitePublishQueueStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    covers = await Directory.systemTemp.createTemp('belog-queue-test');
    store = SqlitePublishQueueStore(
      db,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
  });

  tearDown(() async {
    await db.close();
    if (await covers.exists()) await covers.delete(recursive: true);
  });

  test('an enqueued publish keeps its text, tags, key and cover', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'Offline title',
      content: 'Offline body',
      tags: const ['flutter', 'offline'],
      idempotencyKey: 'key-1',
      cover: ImageUpload(bytes: Uint8List.fromList(const [1, 2, 3, 4])),
    );

    expect(entry.status, PublishQueueStatus.queued);
    expect(entry.attempts, 0);
    expect(entry.coverFileName, isNotNull);
    expect(File('${covers.path}/${entry.coverFileName}').existsSync(), isTrue);

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.id, entry.id);
    expect(stored.title, 'Offline title');
    expect(stored.content, 'Offline body');
    expect(stored.tags, ['flutter', 'offline']);
    expect(stored.idempotencyKey, 'key-1');
    expect(stored.userId, 'alice');
    expect(stored.coverMimeType, ImageUpload.defaultMimeType);

    final cover = await store.readCover(stored);
    expect(cover?.bytes, [1, 2, 3, 4]);
  });

  test('a cover is optional', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'No cover',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-2',
    );
    expect(entry.coverFileName, isNull);
    expect(await store.readCover(entry), isNull);
  });

  test('a claimed entry is not offered again', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'first',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );

    final claimed = await store.claimNext(userId: 'alice', now: DateTime.now());
    expect(claimed?.id, entry.id);
    expect(claimed?.status, PublishQueueStatus.uploading);
    expect(claimed?.idempotencyKey, 'key-1');

    // The claim is durable: a second drain sees nothing to send.
    expect(await store.claimNext(userId: 'alice', now: DateTime.now()), isNull);
    expect(
      (await store.entries(userId: 'alice')).single.status,
      PublishQueueStatus.uploading,
    );
  });

  test('a retryable failure waits for its backoff window', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'retry me',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.claimNext(userId: 'alice', now: DateTime.now());
    final due = DateTime.now().add(const Duration(minutes: 1));
    await store.recordFailure(
      entry.id,
      errorCode: 'network.offline',
      retryable: true,
      nextAttemptAt: due,
    );

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.queued);
    expect(stored.attempts, 1);
    expect(stored.lastErrorCode, 'network.offline');
    expect(stored.nextAttemptAt, isNotNull);

    // Not due yet: a drain leaves it alone.
    expect(
      await store.claimNext(
        userId: 'alice',
        now: due.subtract(const Duration(seconds: 1)),
      ),
      isNull,
    );
    // Once due, it is claimable again with the same key.
    final again = await store.claimNext(
      userId: 'alice',
      now: due.add(const Duration(seconds: 1)),
    );
    expect(again?.idempotencyKey, 'key-1');
  });

  test('a permanent failure needs a human', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'rejected',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.claimNext(userId: 'alice', now: DateTime.now());
    await store.recordFailure(
      entry.id,
      errorCode: 'client.validation',
      retryable: false,
    );

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.failed);
    expect(stored.nextAttemptAt, isNull);
    expect(await store.claimNext(userId: 'alice', now: DateTime.now()), isNull);
  });

  test('a failure the entry did not cause does not spend its budget', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'signed out',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.claimNext(userId: 'alice', now: DateTime.now());
    await store.recordFailure(
      entry.id,
      errorCode: 'auth.rejected',
      retryable: true,
      nextAttemptAt: DateTime.now(),
      countAttempt: false,
    );

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.attempts, 0);
    expect(stored.status, PublishQueueStatus.queued);
  });

  test('a manual retry re-arms a failed entry', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'retry me',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.claimNext(userId: 'alice', now: DateTime.now());
    await store.recordFailure(
      entry.id,
      errorCode: 'server.error',
      retryable: false,
    );

    await store.retry(entry.id);

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.queued);
    expect(stored.attempts, 0);
    expect(stored.lastErrorCode, isNull);
    final ready = await store.claimNext(userId: 'alice', now: DateTime.now());
    expect(ready, isNotNull);
  });

  test('completing removes the row and its cover file', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'sent',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
      cover: ImageUpload(bytes: Uint8List.fromList(const [9, 9])),
    );
    final coverFile = File('${covers.path}/${entry.coverFileName}');
    expect(coverFile.existsSync(), isTrue);

    await store.complete(entry.id);

    expect(await store.entries(userId: 'alice'), isEmpty);
    expect(coverFile.existsSync(), isFalse);
  });

  test('removing an entry deletes it too', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'cancel me',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.remove(entry.id);
    expect(await store.entries(userId: 'alice'), isEmpty);
  });

  test('release requeues a claimed entry without an attempt', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'interrupted',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.claimNext(userId: 'alice', now: DateTime.now());
    await store.release(entry.id);

    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.status, PublishQueueStatus.queued);
    expect(stored.attempts, 0);
    final ready = await store.claimNext(userId: 'alice', now: DateTime.now());
    expect(ready, isNotNull);
  });

  test('startup repair requeues an interrupted send', () async {
    await store.enqueue(
      userId: 'alice',
      title: 'crashed mid-send',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await store.claimNext(userId: 'alice', now: DateTime.now());
    expect(await store.claimNext(userId: 'alice', now: DateTime.now()), isNull);

    await store.recoverInterrupted();

    // Same key, so replaying is safe: the server dedupes the article.
    final recovered = await store.claimNext(
      userId: 'alice',
      now: DateTime.now(),
    );
    expect(recovered?.idempotencyKey, 'key-1');
  });

  test('entries never cross accounts or backends', () async {
    final other = SqlitePublishQueueStore(
      db,
      apiBaseUrl: _secondBackend,
      directory: covers,
    );
    await store.enqueue(
      userId: 'alice',
      title: 'alice on first',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-a',
    );
    await store.enqueue(
      userId: 'bob',
      title: 'bob on first',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-b',
    );
    await other.enqueue(
      userId: 'alice',
      title: 'alice on second',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-c',
    );

    expect((await store.entries(userId: 'alice')).map((e) => e.title), [
      'alice on first',
    ]);
    expect((await other.entries(userId: 'alice')).map((e) => e.title), [
      'alice on second',
    ]);
    // A claim is scoped the same way.
    final claimed = await other.claimNext(userId: 'alice', now: DateTime.now());
    expect(claimed?.title, 'alice on second');
  });

  test('the queue survives a reopened database', () async {
    final file = File('${covers.path}/queue.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final firstStore = SqlitePublishQueueStore(
      first,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
    await firstStore.enqueue(
      userId: 'alice',
      title: 'across launches',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final secondStore = SqlitePublishQueueStore(
      second,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
    expect((await secondStore.entries(userId: 'alice')).map((e) => e.title), [
      'across launches',
    ]);
  });
}
