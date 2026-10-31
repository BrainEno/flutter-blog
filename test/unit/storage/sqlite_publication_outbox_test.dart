import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/sqlite_publication_outbox.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/queued_publication.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  late Directory dir;
  late File file;
  late AppDatabase db;
  late SqlitePublicationOutbox store;
  var now = DateTime.utc(2026, 10, 1);

  setUp(() async {
    now = DateTime.utc(2026, 10, 1);
    dir = await Directory.systemTemp.createTemp('belog-outbox-');
    file = File('${dir.path}/db.sqlite');
    db = AppDatabase(NativeDatabase(file));
    store = SqlitePublicationOutbox(db, now: () => now);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<QueuedPublication> enqueue({
    String owner = 'alice',
    bool cover = true,
  }) => store.enqueue(
    ownerId: owner,
    title: 'Title',
    content: 'Body',
    tags: const ['tag'],
    coverBytes: cover ? Uint8List.fromList([1, 2, 3]) : null,
    coverMime: cover ? 'image/png' : null,
  );

  Future<void> reopen() async {
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    store = SqlitePublicationOutbox(db, now: () => now);
  }

  test('v4 migration adds outbox without changing old data', () async {
    await SqliteThemePreferenceStore(db).save(ThemeMode.dark);
    await SqliteBlogDraftStore(db).save(
      BlogDraft(
        blogId: null,
        title: 'legacy',
        content: 'keep',
        tags: const [],
        updatedAt: now,
      ),
    );
    await db.writeMetadata('existing', 'preserved');
    await db.close();
    final old = raw.sqlite3.open(file.path);
    old.execute('DROP TABLE publication_outbox');
    old.execute('PRAGMA user_version = 4');
    old.close();
    db = AppDatabase(NativeDatabase(file));
    store = SqlitePublicationOutbox(db, now: () => now);
    expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.dark);
    expect((await SqliteBlogDraftStore(db).load(null))?.content, 'keep');
    expect(await db.readMetadata('existing'), 'preserved');
    expect((await enqueue()).status, PublicationStatus.queued);
    expect(
      (await db.customSelect('PRAGMA user_version').get()).single.read<int>(
        'user_version',
      ),
      5,
    );
  });

  test(
    'snapshot and cover bytes persist; all mutations are owner-scoped',
    () async {
      final item = await enqueue();
      await enqueue(owner: 'bob', cover: false);
      await reopen();
      final alice = (await store.list('alice')).single;
      expect(alice.id, item.id);
      expect(alice.status, PublicationStatus.queued);
      expect(alice.title, 'Title');
      expect(await store.readCover('alice', item.id), [1, 2, 3]);
      expect(await store.readCover('bob', item.id), isNull);
      expect(await store.get('bob', item.id), isNull);
      expect(
        await store.edit(
          'bob',
          item.id,
          title: 'stolen',
          content: 'x',
          tags: const [],
        ),
        isFalse,
      );
      expect(await store.remove('bob', item.id), isFalse);
      expect((await store.list('bob')).single.ownerId, 'bob');
    },
  );

  test('invalid cover is rejected without creating an intent', () async {
    await expectLater(
      store.enqueue(
        ownerId: 'alice',
        title: 't',
        content: 'c',
        tags: const [],
        coverBytes: Uint8List(0),
        coverMime: 'image/png',
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.enqueue(
        ownerId: 'alice',
        title: 't',
        content: 'c',
        tags: const [],
        coverBytes: Uint8List(3),
        coverMime: 'image/gif',
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.enqueue(
        ownerId: 'alice',
        title: 't',
        content: 'c',
        tags: const [],
        coverBytes: Uint8List(SqlitePublicationOutbox.maxCoverBytes + 1),
        coverMime: 'image/png',
      ),
      throwsArgumentError,
    );
    expect(await store.list('alice'), isEmpty);
  });

  test(
    'interrupted media is paused and reupload/removal require consent',
    () async {
      final item = await enqueue();
      expect((await store.claimNext('alice'))?.id, item.id);
      expect(await store.beginMedia('alice', item.id), isTrue);
      await reopen();
      await store.recoverInterrupted();
      final recovered = (await store.get('alice', item.id))!;
      expect(recovered.status, PublicationStatus.failed);
      expect(recovered.phase, PublicationPhase.mediaUncertain);
      expect(recovered.lastErrorCode, 'media.outcomeUnknown');
      expect(recovered.possibleOrphan, isTrue);
      expect(await store.claimNext('alice'), isNull);
      expect(await store.retry('alice', item.id), isFalse);
      expect(await store.remove('alice', item.id), isFalse);
      expect(await store.removeCover('alice', item.id), isFalse);
      expect(
        await store.retry('alice', item.id, acceptMediaReupload: true),
        isTrue,
      );
      expect((await store.claimNext('alice'))?.phase, PublicationPhase.ready);
      expect(await store.beginMedia('alice', item.id), isTrue);
      expect(
        await store.saveUploadedMedia(
          'alice',
          item.id,
          'https://api.invalid/asset',
        ),
        isTrue,
      );
      expect((await store.get('alice', item.id))?.possibleOrphan, isTrue);
      expect(
        await store.failAttempt(
          'alice',
          item.id,
          code: 'auth.ownerUnavailable',
        ),
        isTrue,
      );
      expect(await store.remove('alice', item.id), isFalse);
      expect(
        await store.remove('alice', item.id, acceptPossibleOrphan: true),
        isTrue,
      );
    },
  );

  test(
    'unknown article remains frozen; only verified reconciliation completes it',
    () async {
      final item = await enqueue();
      await store.claimNext('alice');
      const body = '{"slug":"stable","contentBlocks":[{"id":"fixed"}]}';
      expect(await store.beginArticle('alice', item.id, body), isTrue);
      await reopen();
      await store.recoverInterrupted();
      final recovered = (await store.get('alice', item.id))!;
      expect(recovered.status, PublicationStatus.failed);
      expect(recovered.articleOutcomeUncertain, isTrue);
      expect(recovered.requestJson, body);
      expect(await store.retry('alice', item.id), isFalse);
      expect(
        await store.edit(
          'alice',
          item.id,
          title: 'different',
          content: 'different',
          tags: const [],
        ),
        isFalse,
      );
      expect(await store.remove('alice', item.id), isFalse);
      expect(await store.markReconciled('bob', item.id, 'stable'), isFalse);
      expect(await store.markReconciled('alice', item.id, 'stable'), isTrue);
      final confirmed = (await store.get('alice', item.id))!;
      expect(confirmed.status, PublicationStatus.published);
      expect(confirmed.publishedSlug, 'stable');
      expect(await store.readCover('alice', item.id), isNull);
    },
  );

  test('safe interruptions and backoff persist across a restart', () async {
    final item = await enqueue(cover: false);
    await store.claimNext('alice');
    await reopen();
    await store.recoverInterrupted();
    final claimed = (await store.claimNext('alice'))!;
    expect(claimed.attemptCount, 2);
    expect(
      await store.failAttempt(
        'alice',
        item.id,
        code: 'network.unavailable',
        retryAt: now.add(const Duration(seconds: 30)),
      ),
      isTrue,
    );
    await reopen();
    expect(await store.claimNext('alice'), isNull);
    now = now.add(const Duration(seconds: 31));
    expect((await store.claimNext('alice'))?.id, item.id);
  });
}
