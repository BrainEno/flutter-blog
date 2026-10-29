import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:belog/core/theme/theme_preference.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory dir;
  late AppDatabase db;

  setUpAll(() => Isar.initializeIsarCore(download: true));
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

  test(
    'imports actual Isar data once; failure rolls back and can retry',
    () async {
      final old = await Isar.open(
        [ThemePreferenceSchema, BlogSchema, BlogDraftSchema],
        directory: dir.path,
        inspector: false,
      );
      await old.writeTxn(() async {
        await old.themePreferences.put(
          ThemePreference(themeMode: ThemeMode.light)..id = 2,
        );
        await old.themePreferences.put(
          ThemePreference(themeMode: ThemeMode.dark)..id = 9,
        );
        await old.blogDrafts.put(
          BlogDraft(
            blogId: 'a',
            title: 'keep',
            content: 'unsent',
            tags: ['x'],
            updatedAt: DateTime.utc(2024),
          )..id = 7,
        );
        await old.blogs.put(blog('1', 'legacy'));
      });
      await old.close();
      await db.customStatement(
        "CREATE TRIGGER fail_import BEFORE INSERT ON drafts BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(db.importLegacyIfNeeded(dir), throwsA(anything));
      expect(await db.customSelect('SELECT * FROM theme').get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM metadata').get(), isEmpty);
      expect(await File('${dir.path}/default.isar').exists(), isTrue);
      await db.customStatement('DROP TRIGGER fail_import');
      await db.importLegacyIfNeeded(dir);
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
}
