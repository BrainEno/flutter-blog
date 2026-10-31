import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

BlogModel _blog(String id, {DateTime? updatedAt, String? title}) => BlogModel(
  id: id,
  articleId: 'server-$id',
  title: title ?? 'title $id',
  content: 'body $id',
  posterId: 'author',
  imageUrl: '',
  tags: const ['tag'],
  updatedAt: updatedAt ?? DateTime.utc(2025),
  posterName: 'Alice',
);

void main() {
  late Directory dir;
  late File file;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('belog-feed-paging-');
    file = File('${dir.path}/cache.sqlite');
    db = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('pages are bounded and deterministic for equal timestamps', () async {
    final cache = SqliteBlogCache(db);
    await cache.uploadLocalBlogs(
      blogs: [
        _blog('oldest', updatedAt: DateTime.utc(2024)),
        ...List.generate(
          23,
          (i) => _blog('item-${(22 - i).toString().padLeft(2, '0')}'),
        ),
        _blog('newest', updatedAt: DateTime.utc(2026)),
      ],
    );

    final first = await cache.loadBlogs(limit: 10, offset: 0);
    final second = await cache.loadBlogs(limit: 10, offset: 10);
    final third = await cache.loadBlogs(limit: 10, offset: 20);
    final beyond = await cache.loadBlogs(limit: 10, offset: 30);
    final ids = [...first, ...second, ...third].map((blog) => blog.id).toList();
    expect(first, hasLength(10));
    expect(second, hasLength(10));
    expect(third, hasLength(5));
    expect(beyond, isEmpty);
    expect(ids, [
      'newest',
      ...List.generate(23, (i) => 'item-${i.toString().padLeft(2, '0')}'),
      'oldest',
    ]);
    expect(ids.toSet(), hasLength(25));
    expect(first.first.articleId, 'server-newest');
    expect(first.first.posterName, 'Alice');
    expect(second.first.content, 'body item-09');

    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT * FROM blog_cache '
          'ORDER BY updated_at DESC, id ASC LIMIT 10 OFFSET 10',
        )
        .get();
    expect(
      plan.map((row) => row.read<String>('detail')).join(' '),
      contains('blog_cache_feed_order'),
    );
  });

  test(
    'later pages can access rows beyond the old 500-result read cap',
    () async {
      final cache = SqliteBlogCache(db);
      await cache.uploadLocalBlogs(
        blogs: List.generate(
          503,
          (i) => _blog('item-${i.toString().padLeft(3, '0')}'),
        ),
      );

      expect(await cache.loadBlogs(), hasLength(500));
      final last = await cache.loadBlogs(limit: 10, offset: 500);
      expect(last.map((blog) => blog.id), ['item-500', 'item-501', 'item-502']);
      expect(await cache.searchLocalBlogs('title'), hasLength(500));
    },
  );

  test('search still treats wildcard characters literally', () async {
    final cache = SqliteBlogCache(db);
    await cache.uploadLocalBlogs(
      blogs: [
        _blog('literal', title: '100%_MATCH'),
        _blog('other', title: '100xxmatch'),
      ],
    );
    expect((await cache.searchLocalBlogs('%_')).map((b) => b.id), ['literal']);
    expect((await cache.searchLocalBlogs('match')).map((b) => b.id), [
      'literal',
      'other',
    ]);
  });

  test('rejects unbounded or negative pagination arguments', () async {
    final cache = SqliteBlogCache(db);
    await expectLater(cache.loadBlogs(limit: 0), throwsRangeError);
    await expectLater(cache.loadBlogs(limit: 501), throwsRangeError);
    await expectLater(cache.loadBlogs(offset: -1), throwsRangeError);
  });

  test('v3 upgrade adds the feed index without changing existing data', () async {
    await SqliteThemePreferenceStore(db).save(ThemeMode.dark);
    await SqliteBlogDraftStore(db).save(
      BlogDraft(
        blogId: 'draft-blog',
        title: 'unsent',
        content: 'draft body',
        tags: const ['draft'],
        updatedAt: DateTime.utc(2024),
      ),
    );
    await db.writeMetadata('test-marker', 'preserved');
    await SqliteBlogCache(db).uploadLocalBlogs(blogs: [_blog('cached')]);
    await db.customStatement(
      'INSERT INTO reading_history(user_id, blog_id, title, read_at) VALUES (?, ?, ?, ?)',
      ['user', 'cached', 'history', 1700000000000000],
    );
    await db.close();

    // A v3 install has the same tables but not the new index.
    final old = raw.sqlite3.open(file.path);
    old.execute('DROP INDEX blog_cache_feed_order');
    old.execute('DROP TABLE publication_outbox');
    old.execute('PRAGMA user_version = 3');
    old.close();

    db = AppDatabase(NativeDatabase(file));
    expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.dark);
    expect(
      (await SqliteBlogDraftStore(db).load('draft-blog'))?.content,
      'draft body',
    );
    expect(await db.readMetadata('test-marker'), 'preserved');
    expect(
      (await SqliteBlogCache(db).loadBlogs(limit: 10)).single.id,
      'cached',
    );
    expect(
      (await db.customSelect('SELECT title FROM reading_history').get()).single
          .read<String>('title'),
      'history',
    );
    final indices = await db
        .customSelect('PRAGMA index_list(blog_cache)')
        .get();
    expect(
      indices.map((row) => row.read<String>('name')),
      contains('blog_cache_feed_order'),
    );
    expect(
      (await db.customSelect('PRAGMA user_version').get()).single.read<int>(
        'user_version',
      ),
      5,
    );

    await db.close();
    db = AppDatabase(NativeDatabase(file));
    expect(
      (await SqliteBlogCache(db).loadBlogs(limit: 10)).single.content,
      'body cached',
    );
  });
}
