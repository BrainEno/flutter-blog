import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/datasources/sqlite_draft_store.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../support/structured_article_fixtures.dart';

void main() {
  test('v4 migration retains old Markdown cache, drafts and theme', () async {
    final dir = await Directory.systemTemp.createTemp('structured-v4-');
    final file = File('${dir.path}/old.sqlite');
    final old = raw.sqlite3.open(file.path);
    old.execute('PRAGMA user_version = 4');
    old.execute(
      'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    old.execute(
      'CREATE TABLE theme (id INTEGER PRIMARY KEY, mode TEXT NOT NULL)',
    );
    old.execute("INSERT INTO theme VALUES (0, 'dark')");
    old.execute(
      'CREATE TABLE drafts (id INTEGER PRIMARY KEY AUTOINCREMENT, blog_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    old.execute(
      "INSERT INTO drafts (blog_id, title, content, tags, updated_at) VALUES ('old', 'draft', 'unpublished work', '[]', 1)",
    );
    old.execute(
      "CREATE TABLE blog_cache (id TEXT PRIMARY KEY, article_id TEXT NOT NULL DEFAULT '', title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT)",
    );
    old.execute(
      "INSERT INTO blog_cache (id, title, content, poster_id, image_url, tags, updated_at) VALUES ('old', 'Old title', '# Old Markdown', 'a', '', '[]', 1)",
    );
    old.execute(
      "INSERT INTO blog_cache (id, article_id, title, content, poster_id, image_url, tags, updated_at) VALUES ('remote', 'server-id', 'Possibly rich', 'flattened text', 'a', '', '[]', 1)",
    );
    old.close();

    final db = AppDatabase(NativeDatabase(file));
    try {
      final cache = SqliteBlogCache(db);
      final row = await cache.loadBlogById('old');
      expect(row?.content, '# Old Markdown');
      expect(row?.document, isNull);
      expect(row?.documentJson, isNull);
      final oldRemote = await cache.loadBlogById('remote');
      expect(oldRemote?.content, 'flattened text');
      expect(oldRemote?.document?.supported, isFalse);
      final drafts = SqliteBlogDraftStore(
        db,
        apiBaseUrl: Uri.parse('https://api.example.invalid'),
      );
      expect(await drafts.load('old', userId: 'user-a'), isNull);
      expect(await drafts.hasUnclaimedDrafts(), isTrue);
      expect(
        (await db.customSelect('SELECT content FROM drafts').getSingle())
            .read<String>('content'),
        'unpublished work',
      );
      expect(
        (await db.customSelect('SELECT mode FROM theme').getSingle())
            .read<String>('mode'),
        'dark',
      );
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        13,
      );
      expect(
        (await db.customSelect('PRAGMA table_info(blog_cache)').get()).map(
          (r) => r.read<String>('name'),
        ),
        contains('document_json'),
      );
      // v13 adds the column for the categories an article sits in; a row that
      // predates it reads as "no categories kept", not as an empty taxonomy.
      expect(
        (await db.customSelect('PRAGMA table_info(blog_cache)').get()).map(
          (r) => r.read<String>('name'),
        ),
        contains('categories_json'),
      );
      expect((await cache.loadBlogById('old'))?.categories, isEmpty);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'structured bodies round-trip, corrupt rows warn, replacements clear old bodies',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final cache = SqliteBlogCache(db);
        final rich = BlogModel.fromNowaveArticle(structuredArticle());
        await cache.uploadLocalBlogs(blogs: [rich]);
        final cached = await cache.loadBlogById('structured');
        expect(cached?.document?.supported, isTrue);
        expect(cached?.documentJson, rich.documentJson);
        expect(
          (cached!.document!.blocks.last as ArticleCodeBlock).code,
          '  a\n\n b  \n',
        );
        // Caches never authorize an edit, even after a round trip.
        expect(cached.plainEditorCompatible, isFalse);
        expect((await cache.loadBlogs()).single.document?.blocks, hasLength(7));
        expect(
          (await cache.searchLocalBlogs('Sample')).single.document?.supported,
          isTrue,
        );

        await db.customStatement(
          'UPDATE blog_cache SET document_json = ? WHERE id = ?',
          ['{broken', 'structured'],
        );
        final corrupt = await cache.loadBlogById('structured');
        expect(corrupt?.document?.supported, isFalse);
        expect(corrupt?.content, rich.content);

        final replacement = BlogModel.fromNowaveArticle({
          ...structuredArticle(),
          'contentBlocksVersion': 0,
          'contentBlocks': [
            {'id': 'new', 'type': 'paragraph', 'text': '# New Markdown'},
          ],
        });
        await cache.uploadLocalBlogs(blogs: [replacement]);
        final newer = await cache.loadBlogById('structured');
        expect(newer?.document, isNull);
        expect(newer?.documentJson, isNull);
        expect(newer?.content, '# New Markdown');
      } finally {
        await db.close();
      }
    },
  );

  test('the categories an article sits in survive the cache', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final cache = SqliteBlogCache(db);
      await cache.uploadLocalBlogs(
        blogs: [
          BlogModel.fromNowaveArticle({
            ...structuredArticle(),
            'categories': const [
              {'id': 'cat-1', 'slug': 'essay', 'name': '随笔'},
              {
                'id': 'cat-2',
                'slug': 'poem',
                'name': 'Poetry',
                'description': 'Verse.',
              },
            ],
          }),
        ],
      );

      final cached = await cache.loadBlogById('structured');
      // Names are per language, so an offline row has to carry the ones the
      // server rendered - the catalog is a network read.
      expect(cached?.categories.map((c) => c.name), ['随笔', 'Poetry']);
      expect(cached?.categories.last.description, 'Verse.');
      expect(cached?.categoryIds, ['cat-1', 'cat-2']);

      // Damaged JSON costs the labels, not the offline article.
      await db.customStatement(
        'UPDATE blog_cache SET categories_json = ? WHERE id = ?',
        ['{broken', 'structured'],
      );
      final damaged = await cache.loadBlogById('structured');
      expect(damaged?.categories, isEmpty);
      expect(damaged?.title, cached?.title);
    } finally {
      await db.close();
    }
  });
}
