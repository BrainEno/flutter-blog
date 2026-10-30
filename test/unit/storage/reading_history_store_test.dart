import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  late Directory dir;
  late AppDatabase db;
  late SqliteReadingHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('belog-history-');
    db = AppDatabase(NativeDatabase(File('${dir.path}/history.sqlite')));
    store = SqliteReadingHistoryStore(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Blog blog(String id, {String? posterName}) => Blog(
    id: id,
    title: '标题 $id',
    content: '正文',
    posterId: 'author',
    imageUrl: 'https://api.example.invalid/$id.webp',
    tags: const ['诗歌'],
    updatedAt: DateTime.utc(2025),
    posterName: posterName,
  );

  test('records reads newest-first', () async {
    await store.record(userId: 'u1', blog: blog('a'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.record(userId: 'u1', blog: blog('b'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.record(userId: 'u1', blog: blog('c'));

    final entries = await store.list(userId: 'u1');
    expect(entries.map((e) => e.blogId), ['c', 'b', 'a']);
  });

  test(
    're-reading bumps the entry to the top instead of duplicating',
    () async {
      await store.record(userId: 'u1', blog: blog('a'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.record(userId: 'u1', blog: blog('b'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.record(userId: 'u1', blog: blog('a'));

      final entries = await store.list(userId: 'u1');
      expect(entries.map((e) => e.blogId), ['a', 'b']);
    },
  );

  test('history is scoped per account', () async {
    await store.record(userId: 'u1', blog: blog('a'));
    await store.record(userId: 'u2', blog: blog('b'));

    expect((await store.list(userId: 'u1')).map((e) => e.blogId), ['a']);
    expect((await store.list(userId: 'u2')).map((e) => e.blogId), ['b']);
  });

  test('entries snapshot the display fields', () async {
    await store.record(
      userId: 'u1',
      blog: blog('a', posterName: '作者'),
    );

    final entry = (await store.list(userId: 'u1')).single;
    expect(entry.title, '标题 a');
    expect(entry.posterName, '作者');
    expect(entry.imageUrl, 'https://api.example.invalid/a.webp');
    expect(
      entry.readAt.difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 1)),
    );
  });

  test('a null poster name is stored as an empty string', () async {
    await store.record(userId: 'u1', blog: blog('a', posterName: null));
    expect((await store.list(userId: 'u1')).single.posterName, '');
  });

  test('remove deletes exactly one entry', () async {
    await store.record(userId: 'u1', blog: blog('a'));
    await store.record(userId: 'u1', blog: blog('b'));

    await store.remove(userId: 'u1', blogId: 'a');
    expect((await store.list(userId: 'u1')).map((e) => e.blogId), ['b']);
    // And it never touches another account's entry.
    await store.record(userId: 'u2', blog: blog('a'));
    await store.remove(userId: 'u1', blogId: 'b');
    expect((await store.list(userId: 'u2')).map((e) => e.blogId), ['a']);
  });

  test('clear wipes only the given account', () async {
    await store.record(userId: 'u1', blog: blog('a'));
    await store.record(userId: 'u1', blog: blog('b'));
    await store.record(userId: 'u2', blog: blog('c'));

    await store.clear(userId: 'u1');
    expect(await store.list(userId: 'u1'), isEmpty);
    expect((await store.list(userId: 'u2')).map((e) => e.blogId), ['c']);
  });

  test('a v2 database is upgraded in place and gains reading_history', () async {
    // Rebuild what a v2 install looked like: every pre-v3 table, no
    // reading_history, user_version pinned to 2 (drift reads the schema
    // version from there).
    await db.close();
    final file = File('${dir.path}/v2.sqlite');
    final old = raw.sqlite3.open(file.path);
    old.execute(
      'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    old.execute(
      'CREATE TABLE theme (id INTEGER PRIMARY KEY CHECK (id = 0), mode TEXT NOT NULL)',
    );
    old.execute(
      'CREATE TABLE drafts (id INTEGER PRIMARY KEY AUTOINCREMENT, blog_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    old.execute(
      'CREATE TABLE blog_cache (id TEXT PRIMARY KEY, article_id TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT)',
    );
    old.execute('PRAGMA user_version = 2');
    old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final upgradedStore = SqliteReadingHistoryStore(upgraded);
    await upgradedStore.record(userId: 'u1', blog: blog('upgrade'));
    expect((await upgradedStore.list(userId: 'u1')).single.blogId, 'upgrade');
    // The v2 data is untouched.
    expect(
      await upgraded
          .customSelect(
            'SELECT name FROM sqlite_master WHERE type = \'table\' AND name = \'blog_cache\'',
          )
          .get(),
      isNotEmpty,
    );
  });
}
