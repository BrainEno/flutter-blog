import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/legacy/blog.dart' as legacy;
import 'package:belog/core/storage/legacy/blog_draft.dart' as legacy;
import 'package:belog/core/storage/legacy/theme_preference.dart' as legacy;
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart' as legacy;

void main() {
  late Directory dir;
  late AppDatabase db;

  setUpAll(() => legacy.Isar.initializeIsarCore(download: true));
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('belog-sqlite-');
    db = AppDatabase(NativeDatabase(File('${dir.path}/new.sqlite')));
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  BlogModel blog(String id, String title) => BlogModel(
    id: id,
    title: title,
    content: 'body',
    posterId: 'author',
    imageUrl: 'cover',
    tags: ['one'],
    updatedAt: DateTime.utc(2025),
    posterName: 'Alice',
    posterAvatar: 'avatar',
  );

  test('deleting a cached blog drops only that row', () async {
    final cache = SqliteBlogCache(db);
    await cache.uploadLocalBlogs(blogs: [blog('slug-1', 'one')]);
    await cache.uploadLocalBlogs(blogs: [blog('slug-2', 'two')]);

    await cache.deleteCachedBlog('slug-1');

    expect(await cache.loadBlogById('slug-1'), isNull);
    expect((await cache.loadBlogById('slug-2'))?.title, 'two');
    expect((await cache.loadBlogs()).map((b) => b.id), ['slug-2']);
    // Idempotent: a missing row deletes silently.
    await cache.deleteCachedBlog('slug-1');
  });

  test('fresh database preserves themes, drafts and upserted cache', () async {
    await db.importLegacyIfNeeded(dir);
    final themes = SqliteThemePreferenceStore(db);
    expect(await themes.load(), ThemeMode.system);
    await themes.save(ThemeMode.dark);
    final drafts = SqliteBlogDraftStore(db);
    final draft = BlogDraft(
      blogId: 'a',
      title: 'title',
      content: 'text',
      tags: ['x'],
      updatedAt: DateTime.utc(2024),
    );
    await drafts.save(draft);
    expect((await drafts.load('a'))!.content, 'text');
    final cache = SqliteBlogCache(db);
    await cache.uploadLocalBlogs(blogs: [blog('1', 'old')]);
    await cache.uploadLocalBlogs(
      blogs: [blog('1', 'new'), blog('2', 'second')],
    );
    expect((await cache.loadBlogs()).map((b) => b.id), ['1', '2']);
    expect((await cache.searchLocalBlogs('new')).single.posterName, 'Alice');
    expect(await drafts.discardIfUnchanged(draft), isTrue);
    await db.close();
    db = AppDatabase(NativeDatabase(File('${dir.path}/new.sqlite')));
    await db.importLegacyIfNeeded(dir);
    expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.dark);
    expect(await SqliteBlogDraftStore(db).load('a'), isNull);
  });

  test('deleteDraftsFor clears one scope without touching others', () async {
    await db.importLegacyIfNeeded(dir);
    final store = SqliteBlogDraftStore(db);
    await store.save(
      BlogDraft(
        blogId: 'a',
        title: 'a',
        content: 'c',
        tags: [],
        updatedAt: DateTime.utc(2024),
      ),
    );
    await store.save(
      BlogDraft(
        blogId: 'b',
        title: 'b',
        content: 'c',
        tags: [],
        updatedAt: DateTime.utc(2024),
      ),
    );
    await store.save(
      BlogDraft(
        blogId: null,
        title: 'new',
        content: 'c',
        tags: [],
        updatedAt: DateTime.utc(2024),
      ),
    );

    final deleted = await store.deleteDraftsFor('a');
    expect(deleted, 1);
    expect(await store.load('a'), isNull);
    expect((await store.load('b'))!.title, 'b');
    expect((await store.load(null))!.title, 'new');
  });

  test(
    'deleteDraftsFor with olderThan keeps drafts edited during upload',
    () async {
      await db.importLegacyIfNeeded(dir);
      final store = SqliteBlogDraftStore(db);
      final publishStarted = DateTime.utc(2025, 1, 1);

      // The store keeps one row per scope, so different scopes play the two
      // roles: an old draft that predates a publish, and one whose updated_at
      // is newer because the user typed while the upload was in flight.
      await store.save(
        BlogDraft(
          blogId: 'stale',
          title: 'pre-publish',
          content: 'c',
          tags: [],
          updatedAt: DateTime.utc(2024),
        ),
      );
      await store.save(
        BlogDraft(
          blogId: 'fresh',
          title: 'typed-during-upload',
          content: 'c',
          tags: [],
          updatedAt: DateTime.utc(2025, 6, 1),
        ),
      );

      expect(
        await store.deleteDraftsFor('stale', olderThan: publishStarted),
        1,
      );
      expect(await store.load('stale'), isNull);

      expect(
        await store.deleteDraftsFor('fresh', olderThan: publishStarted),
        0,
      );
      expect((await store.load('fresh'))!.title, 'typed-during-upload');
    },
  );

  test(
    'drafts are scoped and stale snapshots cannot discard newer work',
    () async {
      await db.importLegacyIfNeeded(dir);
      final store = SqliteBlogDraftStore(db);
      final old = BlogDraft(
        blogId: 'a',
        title: 'old',
        content: 'old',
        tags: [],
        updatedAt: DateTime.utc(2024),
      );
      final other = BlogDraft(
        blogId: null,
        title: 'new article',
        content: 'keep',
        tags: [],
        updatedAt: DateTime.utc(2024),
      );
      await store.save(old);
      await store.save(other);
      final replacement = BlogDraft(
        blogId: 'a',
        title: 'new',
        content: 'new',
        tags: [],
        updatedAt: DateTime.utc(2025),
      );
      await store.save(replacement);
      expect(replacement.id, old.id);
      expect(await store.discardIfUnchanged(old), isFalse);
      expect((await store.load('a'))!.content, 'new');
      expect((await store.load(null))!.content, 'keep');
    },
  );

  test(
    'imports actual Isar data once; failure rolls back and can retry',
    () async {
      final old = await legacy.Isar.open(
        [
          legacy.ThemePreferenceSchema,
          legacy.BlogSchema,
          legacy.BlogDraftSchema,
        ],
        directory: dir.path,
        inspector: false,
      );
      await old.writeTxn(() async {
        await old.themePreferences.put(
          legacy.ThemePreference(themeMode: ThemeMode.light)..id = 2,
        );
        await old.themePreferences.put(
          legacy.ThemePreference(themeMode: ThemeMode.dark)..id = 9,
        );
        await old.blogDrafts.put(
          legacy.BlogDraft(
            blogId: 'a',
            title: 'keep',
            content: 'unsent',
            tags: ['x'],
            updatedAt: DateTime.utc(2024),
          )..id = 7,
        );
        await old.blogs.put(
          legacy.Blog(
            iid: legacy.Isar.autoIncrement,
            id: '1',
            title: 'legacy',
            content: 'body',
            posterId: 'author',
            imageUrl: 'cover',
            tags: ['one'],
            updatedAt: DateTime.utc(2025),
            posterName: 'Alice',
            posterAvatar: 'avatar',
          ),
        );
      });
      await old.close();
      final legacyBytes = await File('${dir.path}/default.isar').readAsBytes();
      await db.customStatement(
        "CREATE TRIGGER fail_import BEFORE INSERT ON drafts BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(db.importLegacyIfNeeded(dir), throwsA(anything));
      expect(await db.customSelect('SELECT * FROM theme').get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM metadata').get(), isEmpty);
      expect(await File('${dir.path}/default.isar').readAsBytes(), legacyBytes);
      await db.customStatement('DROP TRIGGER fail_import');
      await db.importLegacyIfNeeded(dir);
      expect(await File('${dir.path}/default.isar').readAsBytes(), legacyBytes);
      expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.dark);
      expect((await SqliteBlogDraftStore(db).load('a'))!.content, 'unsent');
      expect(
        (await SqliteBlogCache(db).loadBlogs()).single.posterName,
        'Alice',
      );
      await SqliteThemePreferenceStore(db).save(ThemeMode.light);
      await db.importLegacyIfNeeded(dir);
      expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.light);
    },
  );

  test('a v1 database migrates to v2: blog_cache gains article_id and keeps '
      'its rows', () async {
    await db.close();
    final file = File('${dir.path}/v1.sqlite');
    final rawDb = raw.sqlite3.open(file.path);
    rawDb.execute("PRAGMA user_version = 1");
    rawDb.execute(
      'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    rawDb.execute(
      'CREATE TABLE theme (id INTEGER PRIMARY KEY CHECK (id = 0), mode TEXT NOT NULL)',
    );
    rawDb.execute(
      'CREATE TABLE drafts (id INTEGER PRIMARY KEY AUTOINCREMENT, blog_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    rawDb.execute(
      "CREATE TABLE blog_cache (id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT)",
    );
    rawDb.execute(
      "INSERT INTO blog_cache(id, title, content, poster_id, image_url, tags, updated_at, poster_name, poster_avatar) "
      "VALUES ('old-id', '旧文', '正文', 'author', 'cover', '[\"诗歌\"]', 1700000000000000, 'Alice', 'avatar')",
    );
    rawDb.close();

    final migrated = AppDatabase(NativeDatabase(file));
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    final columns = await migrated
        .customSelect('PRAGMA table_info(blog_cache)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('article_id'),
    );
    final cached = await SqliteBlogCache(migrated).loadBlogs();
    expect(cached.single.id, 'old-id');
    expect(cached.single.title, '旧文');
    expect(cached.single.articleId, '');
  });
}
