import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/data/datasources/sqlite_publish_queue_store.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

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

  test(
    'an already selected media-library cover survives queue storage',
    () async {
      const coverUrl =
          'https://api.example.invalid/api/v1/media/64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01';
      final entry = await store.enqueue(
        userId: 'alice',
        title: 'Reuse media',
        content: 'body',
        tags: const [],
        idempotencyKey: 'key-media-library',
        coverUrl: coverUrl,
        kind: PublishQueueKind.edit,
        targetId: 'article-1',
        locale: 'zh-CN',
      );

      expect(entry.coverUrl, coverUrl);
      expect(entry.coverFileName, isNull);
      final stored = (await store.entries(userId: 'alice')).single;
      expect(stored.coverUrl, coverUrl);
      expect(stored.targetId, 'article-1');
      expect(stored.locale, 'zh-CN');
    },
  );

  test(
    'the queued category survives an untouched and a cleared picker',
    () async {
      await store.enqueue(
        userId: 'alice',
        title: 'No pick',
        content: 'body',
        tags: const [],
        idempotencyKey: 'key-untouched',
      );
      await store.enqueue(
        userId: 'alice',
        title: 'Picked',
        content: 'body',
        tags: const [],
        idempotencyKey: 'key-picked',
        categoryIds: const ['cat-1'],
      );
      await store.enqueue(
        userId: 'alice',
        title: 'Cleared',
        content: 'body',
        tags: const [],
        idempotencyKey: 'key-cleared',
        categoryIds: const [],
      );

      final byTitle = {
        for (final entry in await store.entries(userId: 'alice'))
          entry.title: entry.categoryIds,
      };
      // Null is "never touched", which the retry must be able to tell apart from
      // "the author removed the category" - the two write differently.
      expect(byTitle['No pick'], isNull);
      expect(byTitle['Picked'], ['cat-1']);
      expect(byTitle['Cleared'], isEmpty);
    },
  );

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

  test('the uploaded cover URL is remembered and survives a reopen', () async {
    final file = File('${covers.path}/cover-url.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final firstStore = SqlitePublishQueueStore(
      first,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
    final entry = await firstStore.enqueue(
      userId: 'alice',
      title: 'with cover',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
      cover: ImageUpload(bytes: Uint8List.fromList(const [1, 2, 3])),
    );
    expect(entry.coverUrl, isNull);
    await firstStore.recordCoverUrl(entry.id, url: 'https://cdn/cover-1.png');
    // The bytes stay on disk: the URL is what a retry needs, the file is only
    // a fallback for entries queued before the URL was recorded.
    expect(await firstStore.readCover(entry), isNotNull);
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final secondStore = SqlitePublishQueueStore(
      second,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
    final reopened = (await secondStore.entries(userId: 'alice')).single;
    expect(reopened.coverUrl, 'https://cdn/cover-1.png');
    expect(reopened.idempotencyKey, 'key-1');
  });

  test('a claimed entry keeps the cover URL it already recorded', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'with cover',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
      cover: ImageUpload(bytes: Uint8List.fromList(const [1, 2, 3])),
    );
    await store.recordCoverUrl(entry.id, url: 'https://cdn/cover-1.png');

    final claimed = await store.claimNext(userId: 'alice', now: DateTime.now());

    expect(claimed?.coverUrl, 'https://cdn/cover-1.png');
    expect(claimed?.status, PublishQueueStatus.uploading);
  });

  test('a v8 queue upgrades in place and gains the cover URL column', () async {
    final file = File('${covers.path}/legacy-v8.sqlite');
    final old = raw.sqlite3.open(file.path);
    old.execute('PRAGMA user_version = 8');
    old.execute(
      'CREATE TABLE publish_queue (id TEXT PRIMARY KEY, backend TEXT NOT NULL, '
      'user_id TEXT NOT NULL, idempotency_key TEXT NOT NULL, '
      'title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, '
      'cover_file TEXT, cover_mime TEXT, state TEXT NOT NULL, '
      'attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER, '
      'last_error_code TEXT, created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL)',
    );
    old.execute(
      'CREATE INDEX publish_queue_due '
      'ON publish_queue(backend, user_id, state, created_at)',
    );
    old.execute(
      'INSERT INTO publish_queue(id, backend, user_id, idempotency_key, '
      'title, content, tags, cover_file, cover_mime, state, attempts, '
      'next_attempt_at, last_error_code, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, 1, NULL, ?, ?, ?)',
      [
        'legacy-entry',
        backendKeyOf(_firstBackend),
        'alice',
        'key-legacy',
        'legacy title',
        'legacy body',
        '["old"]',
        'queued',
        'network.offline',
        DateTime.utc(2026, 11, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 11, 1).microsecondsSinceEpoch,
      ],
    );
    old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final legacyStore = SqlitePublishQueueStore(
      upgraded,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );

    final row = (await legacyStore.entries(userId: 'alice')).single;
    expect(row.id, 'legacy-entry');
    expect(row.title, 'legacy title');
    expect(row.idempotencyKey, 'key-legacy');
    expect(row.attempts, 1);
    // NULL reads as "not uploaded yet", which is what v8 did on every attempt.
    expect(row.coverUrl, isNull);

    // The new column is usable right after the upgrade.
    await legacyStore.recordCoverUrl(
      'legacy-entry',
      url: 'https://cdn/legacy.png',
    );
    expect(
      (await legacyStore.entries(userId: 'alice')).single.coverUrl,
      'https://cdn/legacy.png',
    );
    final version = await upgraded
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 16);
  });

  test('a pre-v8 database gains the queue with cover_url', () async {
    // The v8 step creates the table in its current shape, so the v9 step must
    // not try to add the column a second time.
    final file = File('${covers.path}/legacy-v7.sqlite');
    final old = raw.sqlite3.open(file.path);
    old.execute('PRAGMA user_version = 7');
    old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final legacyStore = SqlitePublishQueueStore(
      upgraded,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );

    expect(await legacyStore.entries(userId: 'alice'), isEmpty);
    final entry = await legacyStore.enqueue(
      userId: 'alice',
      title: 'after the upgrade',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-1',
    );
    expect(entry.coverUrl, isNull);
    await legacyStore.recordCoverUrl(
      entry.id,
      url: 'https://cdn/after-upgrade.png',
    );
    expect(
      (await legacyStore.entries(userId: 'alice')).single.coverUrl,
      'https://cdn/after-upgrade.png',
    );
  });

  test('an edit entry keeps the article it updates', () async {
    final file = File('${covers.path}/edit.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final firstStore = SqlitePublishQueueStore(
      first,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
    final entry = await firstStore.enqueue(
      userId: 'alice',
      title: 'new title',
      content: 'new body',
      tags: const ['tag'],
      idempotencyKey: 'key-edit',
      kind: PublishQueueKind.edit,
      targetId: 'my-slug',
    );
    expect(entry.kind, PublishQueueKind.edit);
    expect(entry.targetId, 'my-slug');
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final secondStore = SqlitePublishQueueStore(
      second,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );
    final reopened = (await secondStore.entries(userId: 'alice')).single;
    expect(reopened.kind, PublishQueueKind.edit);
    expect(reopened.targetId, 'my-slug');
    expect(reopened.title, 'new title');
  });

  test('an edit without a target is refused', () async {
    expect(
      () => store.enqueue(
        userId: 'alice',
        title: 'orphan edit',
        content: 'body',
        tags: const [],
        idempotencyKey: 'key-1',
        kind: PublishQueueKind.edit,
      ),
      throwsArgumentError,
    );
    expect(await store.entries(userId: 'alice'), isEmpty);
  });

  test('a v9 queue upgrades and reads its rows as new articles', () async {
    final file = File('${covers.path}/legacy-v9.sqlite');
    final old = raw.sqlite3.open(file.path);
    old.execute('PRAGMA user_version = 9');
    old.execute(
      'CREATE TABLE publish_queue (id TEXT PRIMARY KEY, backend TEXT NOT NULL, '
      'user_id TEXT NOT NULL, idempotency_key TEXT NOT NULL, '
      'title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, '
      'cover_file TEXT, cover_mime TEXT, cover_url TEXT, '
      'state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, '
      'next_attempt_at INTEGER, last_error_code TEXT, '
      'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    );
    old.execute(
      'CREATE INDEX publish_queue_due '
      'ON publish_queue(backend, user_id, state, created_at)',
    );
    old.execute(
      'INSERT INTO publish_queue(id, backend, user_id, idempotency_key, '
      'title, content, tags, cover_file, cover_mime, cover_url, state, '
      'attempts, next_attempt_at, last_error_code, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, 0, NULL, NULL, ?, ?)',
      [
        'v9-create',
        backendKeyOf(_firstBackend),
        'alice',
        'key-v9',
        'old row',
        'body',
        '[]',
        'https://cdn/v9.png',
        'queued',
        DateTime.utc(2026, 11, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 11, 1).microsecondsSinceEpoch,
      ],
    );
    old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final legacyStore = SqlitePublishQueueStore(
      upgraded,
      apiBaseUrl: _firstBackend,
      directory: covers,
    );

    // A v9 row was a publish waiting to create an article; it stays one.
    final row = (await legacyStore.entries(userId: 'alice')).single;
    expect(row.kind, PublishQueueKind.create);
    expect(row.targetId, isNull);
    expect(row.coverUrl, 'https://cdn/v9.png');

    // The v9 row predates editions, so nothing is recorded and a retry falls
    // back to the content language.
    expect(row.locale, isNull);

    // And the new columns are usable straight after the upgrade.
    final edit = await legacyStore.enqueue(
      userId: 'alice',
      title: 'edited',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-edit',
      kind: PublishQueueKind.edit,
      targetId: 'my-slug',
      locale: 'en',
    );
    expect(edit.targetId, 'my-slug');
    expect(edit.locale, 'en');
    expect((await legacyStore.entries(userId: 'alice')).last.locale, 'en');
  });

  test('a queued edit keeps the edition it was queued for', () async {
    final edit = await store.enqueue(
      userId: 'alice',
      title: 'edited',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-edit',
      kind: PublishQueueKind.edit,
      targetId: 'my-slug',
      locale: ' zh-TW ',
    );

    // Normalized on the way in, so a blank value cannot masquerade as an
    // edition and a padded one still names the right translation.
    expect(edit.locale, 'zh-TW');
    final stored = (await store.entries(userId: 'alice')).single;
    expect(stored.locale, 'zh-TW');
  });

  test('a blank edition is stored as unknown', () async {
    final edit = await store.enqueue(
      userId: 'alice',
      title: 'edited',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-edit',
      kind: PublishQueueKind.edit,
      targetId: 'my-slug',
      locale: '   ',
    );

    expect(edit.locale, isNull);
    expect((await store.entries(userId: 'alice')).single.locale, isNull);
  });

  test('a create never carries an edition', () async {
    final entry = await store.enqueue(
      userId: 'alice',
      title: 'new',
      content: 'body',
      tags: const [],
      idempotencyKey: 'key-create',
      locale: 'en',
    );

    // A create names its language in the request body, not in the queue row.
    expect(entry.locale, isNull);
  });
}
