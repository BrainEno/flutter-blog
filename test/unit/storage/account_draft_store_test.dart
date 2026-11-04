import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

final _firstBackend = Uri.parse('https://first.example.invalid/api-root/');
final _secondBackend = Uri.parse('https://second.example.invalid/api-root');

BlogDraft _draft(
  String userId,
  String? blogId,
  String title, {
  int year = 2024,
}) => BlogDraft(
  userId: userId,
  blogId: blogId,
  title: title,
  content: '$title body',
  tags: const ['test'],
  updatedAt: DateTime.utc(year),
);

void main() {
  test(
    'new and same-slug drafts stay separate across accounts and backends',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
      final second = SqliteBlogDraftStore(db, apiBaseUrl: _secondBackend);
      final aliceNew = _draft('alice', null, 'A new');
      final bobNew = _draft('bob', null, 'B new');
      final aliceArticle = _draft('alice', 'same-slug', 'A edit');
      final bobArticle = _draft('bob', 'same-slug', 'B edit');
      await first.save(aliceNew);
      await first.save(bobNew);
      await first.save(aliceArticle);
      await first.save(bobArticle);
      await second.save(_draft('alice', null, 'other backend'));

      expect((await first.load(null, userId: 'alice'))?.title, 'A new');
      expect((await first.load(null, userId: 'bob'))?.title, 'B new');
      expect((await first.load('same-slug', userId: 'alice'))?.title, 'A edit');
      expect((await first.load('same-slug', userId: 'bob'))?.title, 'B edit');
      expect(
        (await second.load(null, userId: 'alice'))?.title,
        'other backend',
      );
      expect(await first.load(null, userId: 'nobody'), isNull);

      // Even a caller forging a row id cannot discard another account's row.
      final forged = _draft('bob', null, 'forged')..id = aliceNew.id;
      expect(await first.discardIfUnchanged(forged), isFalse);
      expect(await first.deleteDraftsFor(null, userId: 'bob'), 1);
      expect((await first.load(null, userId: 'alice'))?.title, 'A new');
      expect(
        (await second.load(null, userId: 'alice'))?.title,
        'other backend',
      );
      expect((await first.load('same-slug', userId: 'bob'))?.title, 'B edit');
    },
  );

  test('backend path is scoped and credentials are not stored', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final first = SqliteBlogDraftStore(
      db,
      apiBaseUrl: Uri.parse(
        'https://user:private@api.example.invalid/one?token=secret#fragment',
      ),
    );
    final second = SqliteBlogDraftStore(
      db,
      apiBaseUrl: Uri.parse('https://api.example.invalid/two'),
    );
    await first.save(_draft('alice', null, 'first path'));
    await second.save(_draft('alice', null, 'second path'));
    expect((await first.load(null, userId: 'alice'))?.title, 'first path');
    expect((await second.load(null, userId: 'alice'))?.title, 'second path');
    final backends =
        (await db.customSelect('SELECT backend FROM account_drafts').get()).map(
          (row) => row.read<String>('backend'),
        );
    expect(backends.every((value) => !value.contains('private')), isTrue);
    expect(backends.every((value) => !value.contains('secret')), isTrue);
    expect(backends.every((value) => !value.contains('fragment')), isTrue);
  });

  test('missing or modified account identifiers fail closed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
    await expectLater(store.load(null, userId: ''), throwsArgumentError);
    expect(
      () => store.save(_draft(' ', null, 'not saved')),
      throwsArgumentError,
    );
    expect(
      () => store.deleteDraftsFor(null, userId: ' alice '),
      throwsArgumentError,
    );
    expect(
      await db.customSelect('SELECT * FROM account_drafts').get(),
      isEmpty,
    );
  });

  test(
    'pending saves are ordered, scoped, and cleanup cannot overtake them',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
      final older = _draft('alice', null, 'old', year: 2024);
      final newer = _draft('alice', null, 'new', year: 2026);
      final other = _draft('bob', null, 'other', year: 2024);
      final first = store.save(older);
      final second = store.save(newer);
      final third = store.save(other);
      final cleanup = store.deleteDraftsFor(
        null,
        userId: 'alice',
        olderThan: DateTime.utc(2025),
      );
      await Future.wait([first, second, third]);
      expect(await cleanup, 0);
      expect((await store.load(null, userId: 'alice'))?.title, 'new');
      expect((await store.load(null, userId: 'bob'))?.title, 'other');
      expect(await store.discardIfUnchanged(older), isFalse);
    },
  );

  test('cutoff equality conservatively keeps the draft', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
    await store.save(_draft('alice', null, 'same instant', year: 2025));
    expect(
      await store.deleteDraftsFor(
        null,
        userId: 'alice',
        olderThan: DateTime.utc(2025),
      ),
      0,
    );
    expect((await store.load(null, userId: 'alice'))?.title, 'same instant');
  });

  test(
    'discard compares content as well as timestamp for the same row',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
      final published = _draft('alice', null, 'published', year: 2024);
      final changed = _draft('alice', null, 'newer contents', year: 2024);
      await store.save(published);
      await store.save(changed);
      expect(changed.id, published.id);
      expect(changed.updatedAt, published.updatedAt);
      expect(await store.discardIfUnchanged(published), isFalse);
      expect(
        (await store.load(null, userId: 'alice'))?.title,
        'newer contents',
      );
      expect(await store.discardIfUnchanged(changed), isTrue);
    },
  );

  test('a failed write does not poison the next queued write', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
    await db.customStatement(
      "CREATE TRIGGER fail_draft BEFORE INSERT ON account_drafts BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
    );
    await expectLater(
      store.save(_draft('alice', null, 'first')),
      throwsA(anything),
    );
    await db.customStatement('DROP TRIGGER fail_draft');
    await store.save(_draft('alice', null, 'second'));
    expect((await store.load(null, userId: 'alice'))?.title, 'second');
  });

  test(
    'v5 ownerless drafts remain intact and hidden after upgrade and restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('belog-draft-v5-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/legacy.sqlite');
      final old = raw.sqlite3.open(file.path);
      old.execute('PRAGMA user_version = 5');
      old.execute(
        'CREATE TABLE drafts (id INTEGER PRIMARY KEY AUTOINCREMENT, blog_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)',
      );
      old.execute(
        "INSERT INTO drafts(id, blog_id, title, content, tags, updated_at) VALUES (7, NULL, 'legacy title', 'legacy body', '[\"old\"]', 42)",
      );
      old.execute(
        'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      old.execute("INSERT INTO metadata VALUES ('marker', 'retained')");
      old.close();

      var db = AppDatabase(NativeDatabase(file));
      var store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
      expect(await store.hasUnclaimedDrafts(), isTrue);
      expect(await store.load(null, userId: 'alice'), isNull);
      expect(await store.load(null, userId: 'bob'), isNull);
      await store.save(_draft('alice', null, 'new scoped draft'));
      expect(await store.deleteDraftsFor(null, userId: 'bob'), 0);
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      try {
        store = SqliteBlogDraftStore(db, apiBaseUrl: _firstBackend);
        expect(
          (await store.load(null, userId: 'alice'))?.title,
          'new scoped draft',
        );
        expect(await store.load(null, userId: 'bob'), isNull);
        expect(await store.hasUnclaimedDrafts(), isTrue);
        final legacy = await db
            .customSelect('SELECT * FROM drafts')
            .getSingle();
        expect(legacy.read<int>('id'), 7);
        expect(legacy.readNullable<String>('blog_id'), isNull);
        expect(legacy.read<String>('title'), 'legacy title');
        expect(legacy.read<String>('content'), 'legacy body');
        expect(legacy.read<String>('tags'), '["old"]');
        expect(legacy.read<int>('updated_at'), 42);
        expect(await db.readMetadata('marker'), 'retained');
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 6);
      } finally {
        await db.close();
      }
    },
  );
}
