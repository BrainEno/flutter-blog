import 'dart:io';

import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/datasources/sqlite_reading_history_store.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final _one = Uri.parse('https://one.example.invalid/v1');
final _two = Uri.parse('https://two.example.invalid/v1');
final _revision = ArticleRevision.parse('9223372036854775807')!;

BlogModel _blog(String id, {String title = 'title'}) => BlogModel(
  id: id,
  articleRevision: _revision,
  title: title,
  content: 'content $id',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

void main() {
  test(
    'cache and history isolate reads, writes, search and deletes per backend',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final a = SqliteBlogCache(db, apiBaseUrl: _one);
      final b = SqliteBlogCache(db, apiBaseUrl: _two);
      await a.uploadLocalBlogs(blogs: [_blog('same', title: 'one')]);
      await b.uploadLocalBlogs(blogs: [_blog('same', title: 'two')]);
      expect((await a.loadBlogById('same'))!.title, 'one');
      expect((await b.loadBlogById('same'))!.title, 'two');
      expect(await a.searchLocalBlogs('two'), isEmpty);
      expect(await b.searchLocalBlogs('one'), isEmpty);
      await a.deleteCachedBlog('same');
      expect(await a.loadBlogById('same'), isNull);
      expect((await b.loadBlogById('same'))!.title, 'two');
      final historyA = SqliteReadingHistoryStore(db, apiBaseUrl: _one);
      final historyB = SqliteReadingHistoryStore(db, apiBaseUrl: _two);
      await historyA.record(
        userId: 'u',
        blog: _blog('same', title: 'one'),
      );
      await historyB.record(
        userId: 'u',
        blog: _blog('same', title: 'two'),
      );
      await historyA.record(
        userId: 'v',
        blog: _blog('same', title: 'other account'),
      );
      await historyA.remove(userId: 'u', blogId: 'same');
      expect(await historyA.list(userId: 'u'), isEmpty);
      expect((await historyB.list(userId: 'u')).single.title, 'two');
      await historyA.clear(userId: 'v');
      expect((await historyB.list(userId: 'u')).single.title, 'two');
    },
  );

  test(
    'cache preserves an opaque article revision for a later safe edit',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = SqliteBlogCache(db, apiBaseUrl: _one);

      await cache.uploadLocalBlogs(blogs: [_blog('revision')]);

      expect(
        (await cache.loadBlogById('revision'))?.articleRevision,
        _revision,
      );
    },
  );

  test(
    'bounded LRU keeps a recently read item and does not evict another backend or locale',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var clock = DateTime.utc(2026);
      final locale = ContentLocale();
      final a = SqliteBlogCache(
        db,
        apiBaseUrl: _one,
        contentLocale: locale,
        now: () => clock,
      );
      final b = SqliteBlogCache(db, apiBaseUrl: _two, now: () => clock);
      for (var i = 0; i < 250; i++) {
        await a.uploadLocalBlogs(
          blogs: [_blog('item-${i.toString().padLeft(3, '0')}')],
        );
        clock = clock.add(const Duration(seconds: 1));
      }
      await b.uploadLocalBlogs(blogs: [_blog('other-backend')]);
      expect(await a.loadBlogById('item-000'), isNotNull);
      clock = clock.add(const Duration(seconds: 1));
      await a.uploadLocalBlogs(blogs: [_blog('new')]);
      expect(await a.loadBlogById('item-000'), isNotNull);
      expect(await a.loadBlogById('item-001'), isNull);
      expect(await a.loadBlogs(), hasLength(250));
      expect(await b.loadBlogById('other-backend'), isNotNull);
      locale.update(ContentLanguage.en);
      await a.uploadLocalBlogs(blogs: [_blog('english')]);
      expect((await a.loadBlogs()).single.id, 'english');
      locale.update(ContentLanguage.zh);
      expect(await a.loadBlogs(), hasLength(250));
    },
  );

  test('an advisory LRU touch failure does not block offline reading', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = SqliteBlogCache(db, apiBaseUrl: _one);
    await cache.uploadLocalBlogs(blogs: [_blog('saved')]);
    await db.customStatement(
      "CREATE TRIGGER block_touch BEFORE UPDATE ON blog_cache BEGIN SELECT RAISE(ABORT, 'disk read-only'); END",
    );
    expect((await cache.loadBlogById('saved'))!.content, 'content saved');
    expect((await cache.loadBlogs()).single.id, 'saved');
  });

  test('a failed batch rolls back its writes and eviction', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = SqliteBlogCache(db, apiBaseUrl: _one);
    await cache.uploadLocalBlogs(blogs: [_blog('existing')]);
    await db.customStatement(
      "CREATE TRIGGER reject_bad BEFORE INSERT ON blog_cache WHEN NEW.id = 'bad' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      cache.uploadLocalBlogs(blogs: [_blog('good'), _blog('bad')]),
      throwsA(isA<Object>()),
    );
    expect(await cache.loadBlogById('existing'), isNotNull);
    expect(await cache.loadBlogById('good'), isNull);
  });

  test(
    'old ownerless rows stay intact but are not attributed to a new backend after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('scoped-cache-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('DROP TABLE blog_cache');
      raw.execute('DROP TABLE reading_history');
      raw.execute(
        "CREATE TABLE blog_cache (id TEXT NOT NULL, content_locale TEXT NOT NULL, article_id TEXT NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT, document_json TEXT, categories_json TEXT, PRIMARY KEY(id, content_locale))",
      );
      raw.execute(
        "INSERT INTO blog_cache VALUES ('old', 'en', 'id', 'title', 'body', 'author', '', '[]', 12, null, null, null, null)",
      );
      raw.execute(
        "CREATE TABLE reading_history (user_id TEXT NOT NULL, blog_id TEXT NOT NULL, title TEXT NOT NULL, poster_name TEXT NOT NULL, image_url TEXT NOT NULL, read_at INTEGER NOT NULL, PRIMARY KEY(user_id, blog_id))",
      );
      raw.execute(
        "INSERT INTO reading_history VALUES ('user', 'old', 'private history', '', '', 42)",
      );
      raw.execute('PRAGMA user_version = 16');
      raw.close();
      db = AppDatabase(NativeDatabase(file));
      final history = SqliteReadingHistoryStore(db, apiBaseUrl: _one);
      expect(await history.list(userId: 'user'), isEmpty);
      expect(
        await SqliteBlogCache(db, apiBaseUrl: _one).loadBlogById('old'),
        isNull,
      );
      final legacyCache = await db
          .customSelect("SELECT * FROM blog_cache WHERE backend = ''")
          .getSingle();
      expect(legacyCache.read<String>('content'), 'body');
      // A v16 cache row has no provable server condition. The v18 migration
      // keeps it readable but leaves the new condition null, so it can never
      // authorize an unconditional update.
      expect(legacyCache.readNullable<String>('article_revision'), isNull);
      expect(
        (await db
                .customSelect(
                  "SELECT title FROM reading_history WHERE backend = ''",
                )
                .getSingle())
            .read<String>('title'),
        'private history',
      );
      await history.clear(userId: 'user');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      expect(
        (await db
                .customSelect(
                  "SELECT title FROM reading_history WHERE backend = ''",
                )
                .getSingle())
            .read<String>('title'),
        'private history',
      );
      final maintenance = SqliteReadingHistoryStore(db, apiBaseUrl: _one);
      expect(await maintenance.hasUnattributedHistory(), isTrue);
      await maintenance.record(userId: 'user', blog: _blog('current'));
      await maintenance.clearUnattributedHistory();
      expect(await maintenance.hasUnattributedHistory(), isFalse);
      expect((await maintenance.list(userId: 'user')).single.blogId, 'current');
      await db.close();
    },
  );

  test(
    'production file connection enables WAL and bounded busy timeout',
    () async {
      final dir = await Directory.systemTemp.createTemp('wal-cache-');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase.open(File('${dir.path}/cache.sqlite'));
      addTearDown(db.close);
      final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
      expect(mode.read<String>('journal_mode').toLowerCase(), 'wal');
      final timeout = await db.customSelect('PRAGMA busy_timeout').getSingle();
      expect(timeout.read<int>('timeout'), 5000);
    },
  );
}
