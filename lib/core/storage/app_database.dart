import 'dart:convert';
import 'dart:io';

import 'package:belog/core/storage/legacy/blog.dart' as legacy;
import 'package:belog/core/storage/legacy/blog_draft.dart' as legacy;
import 'package:belog/core/storage/legacy/theme_preference.dart' as legacy;
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:isar_community/isar.dart' as legacy;

/// SQLite is the live store. Isar is opened only for the one-time import.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE theme (id INTEGER PRIMARY KEY CHECK (id = 0), mode TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE drafts (id INTEGER PRIMARY KEY AUTOINCREMENT, blog_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)',
      );
      await customStatement('CREATE INDEX drafts_blog_id ON drafts(blog_id)');
      await _createBlogCache();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2 adds the no-wave server article id. Existing rows keep their
        // Supabase-era identifiers (their `id` no longer resolves on the
        // new backend, but the rows stay readable as offline history).
        await customStatement(
          'ALTER TABLE blog_cache ADD COLUMN article_id TEXT NOT NULL DEFAULT \'\'',
        );
      }
    },
  );

  /// The offline blog cache. `id` is the article's public slug on the
  /// no-wave backend; `article_id` is the server UUID needed for writes.
  Future<void> _createBlogCache() => customStatement(
    'CREATE TABLE blog_cache (id TEXT PRIMARY KEY, article_id TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT)',
  );

  /// Run before exposing this database to any UI. A marker and every imported
  /// row commit together; failure leaves the old database intact and retries
  /// on the next launch. The original files are intentionally never deleted.
  Future<void> importLegacyIfNeeded(Directory directory) async {
    final marker = await customSelect(
      "SELECT value FROM metadata WHERE key = 'isar_import_v1'",
    ).getSingleOrNull();
    if (marker != null) return;

    final legacyFile = File('${directory.path}/default.isar');
    legacy.Isar? old;
    Directory? copyDirectory;
    try {
      if (await legacyFile.exists()) {
        // Opening Isar can itself modify schema or database geometry. Never
        // let a failed or interrupted import alter the user's only copy.
        copyDirectory = await Directory.systemTemp.createTemp(
          'belog-isar-import-',
        );
        await legacyFile.copy('${copyDirectory.path}/default.isar');
        old = await legacy.Isar.open(
          [
            legacy.ThemePreferenceSchema,
            legacy.BlogSchema,
            legacy.BlogDraftSchema,
          ],
          directory: copyDirectory.path,
          inspector: false,
        );
      }
      final preferences = old == null
          ? <legacy.ThemePreference>[]
          : await old.themePreferences.where().anyId().findAll();
      final drafts = old == null
          ? <legacy.BlogDraft>[]
          : await old.blogDrafts.where().anyId().findAll();
      final blogs = old == null
          ? <legacy.Blog>[]
          : await old.blogs.where().anyIid().findAll();
      await transaction(() async {
        if (preferences.isNotEmpty) {
          final latest = preferences.reduce((a, b) => a.id > b.id ? a : b);
          await setTheme(latest.themeMode);
        }
        for (final draft in drafts) {
          await customStatement(
            'INSERT INTO drafts(id, blog_id, title, content, tags, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              draft.id,
              draft.blogId,
              draft.title,
              draft.content,
              jsonEncode(draft.tags),
              draft.updatedAt.microsecondsSinceEpoch,
            ],
          );
        }
        for (final blog in blogs) {
          await upsertBlog(
            BlogModel(
              id: blog.id,
              title: blog.title,
              content: blog.content,
              posterId: blog.posterId,
              imageUrl: blog.imageUrl,
              tags: blog.tags,
              updatedAt: blog.updatedAt,
              posterName: blog.posterName,
              posterAvatar: blog.posterAvatar,
            ),
          );
        }
        await customStatement(
          "INSERT INTO metadata(key, value) VALUES ('isar_import_v1', 'complete')",
        );
      });
    } finally {
      try {
        await old?.close();
      } finally {
        if (copyDirectory != null && await copyDirectory.exists()) {
          await copyDirectory.delete(recursive: true);
        }
      }
    }
  }

  Future<void> setTheme(ThemeMode mode) => customStatement(
    'INSERT INTO theme(id, mode) VALUES (0, ?) ON CONFLICT(id) DO UPDATE SET mode = excluded.mode',
    [mode.name],
  );

  /// Reads a `metadata` value, or null when the key is absent.
  Future<String?> readMetadata(String key) async {
    final rows = await customSelect(
      'SELECT value FROM metadata WHERE key = ? LIMIT 1',
      variables: [Variable<String>(key)],
    ).get();
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  Future<void> writeMetadata(String key, String value) => customStatement(
    'INSERT INTO metadata(key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  Future<void> deleteMetadata(String key) =>
      customStatement('DELETE FROM metadata WHERE key = ?', [key]);

  /// Drops a cached article row by its business id (slug).
  Future<void> deleteBlogCacheRow(String id) =>
      customStatement('DELETE FROM blog_cache WHERE id = ?', [id]);

  Future<void> upsertBlog(BlogModel blog) => customStatement(
    '''
    INSERT INTO blog_cache(id, article_id, title, content, poster_id, image_url, tags, updated_at, poster_name, poster_avatar)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET article_id = excluded.article_id, title = excluded.title, content = excluded.content,
      poster_id = excluded.poster_id, image_url = excluded.image_url, tags = excluded.tags,
      updated_at = excluded.updated_at, poster_name = excluded.poster_name, poster_avatar = excluded.poster_avatar
    ''',
    [
      blog.id,
      blog.articleId,
      blog.title,
      blog.content,
      blog.posterId,
      blog.imageUrl,
      jsonEncode(blog.tags),
      blog.updatedAt.microsecondsSinceEpoch,
      blog.posterName,
      blog.posterAvatar,
    ],
  );
}
