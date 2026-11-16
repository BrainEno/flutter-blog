import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _one = Uri.parse('https://one.example.invalid');
final _two = Uri.parse('https://two.example.invalid');

BlogModel _blog(String id, {String title = 'Title', String body = 'Body'}) =>
    BlogModel(
      id: id,
      articleId: 'article-$id',
      title: title,
      content: body,
      posterId: 'author',
      posterName: 'Writer',
      posterAvatar: 'https://one.example.invalid/avatar.webp',
      imageUrl: 'https://one.example.invalid/cover.webp',
      tags: const ['tag'],
      documentJson: '{"blocks":["Body"]}',
      updatedAt: DateTime.utc(2026, 1, 2),
    );

void main() {
  test(
    'offline library lists and clears only its backend and locale scope',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final language = ContentLocale();
      final one = SqliteBlogCache(
        db,
        apiBaseUrl: _one,
        contentLocale: language,
        now: () => DateTime.utc(2026, 1, 3),
      );
      final two = SqliteBlogCache(
        db,
        apiBaseUrl: _two,
        contentLocale: language,
      );

      await one.uploadLocalBlogs(
        blogs: [_blog('one', title: 'Cached title', body: 'Cached body')],
      );
      await two.uploadLocalBlogs(
        blogs: [_blog('other', title: 'Other server')],
      );
      language.update(ContentLanguage.en);
      await one.uploadLocalBlogs(blogs: [_blog('english', title: 'English')]);
      language.update(ContentLanguage.zh);

      final snapshot = await one.inspectOfflineLibrary();
      expect(snapshot.locale, 'zh-CN');
      expect(snapshot.summary.articleCount, 1);
      expect(
        snapshot.summary.estimatedBytes,
        greaterThan('Cached title'.length),
      );
      expect(snapshot.entries.single.article.id, 'one');
      expect(snapshot.entries.single.article.content, 'Cached body');
      expect(snapshot.entries.single.lastAccessedAt, DateTime.utc(2026, 1, 3));

      await one.clearOfflineLibrary();
      expect((await one.inspectOfflineLibrary()).isEmpty, isTrue);
      expect(
        (await two.inspectOfflineLibrary()).entries.single.article.id,
        'other',
      );
      language.update(ContentLanguage.en);
      expect(
        (await one.inspectOfflineLibrary()).entries.single.article.id,
        'english',
      );
    },
  );

  test('catalog inspection does not refresh LRU timestamps', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var clock = DateTime.utc(2026, 1, 1);
    final cache = SqliteBlogCache(db, apiBaseUrl: _one, now: () => clock);
    await cache.uploadLocalBlogs(blogs: [_blog('one')]);
    clock = clock.add(const Duration(days: 1));

    final before =
        (await db
                .customSelect('SELECT accessed_at FROM blog_cache')
                .getSingle())
            .read<int>('accessed_at');
    final snapshot = await cache.inspectOfflineLibrary();
    final after =
        (await db
                .customSelect('SELECT accessed_at FROM blog_cache')
                .getSingle())
            .read<int>('accessed_at');

    expect(
      snapshot.entries.single.lastAccessedAt.microsecondsSinceEpoch,
      before,
    );
    expect(after, before, reason: 'listing metadata is not article access');
  });

  test('library clear leaves drafts and reading-history tables untouched', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = SqliteBlogCache(db, apiBaseUrl: _one);
    await cache.uploadLocalBlogs(blogs: [_blog('one')]);
    await db.customStatement(
      "INSERT INTO account_drafts(backend,user_id,blog_id,title,content,tags,updated_at) VALUES ('scope','u','draft','Draft','Body','[]',1)",
    );
    await db.customStatement(
      "INSERT INTO reading_history(backend,user_id,blog_id,title,poster_name,image_url,read_at) VALUES ('scope','u','read','Read','','',1)",
    );
    await db.customStatement(
      "INSERT INTO publish_queue(id,backend,user_id,idempotency_key,title,content,tags,state,created_at,updated_at) VALUES ('queue','scope','u','key','Queued','Body','[]','queued',1,1)",
    );

    await cache.clearOfflineLibrary();

    expect(
      await db.customSelect('SELECT id FROM account_drafts').get(),
      hasLength(1),
    );
    expect(
      await db.customSelect('SELECT blog_id FROM reading_history').get(),
      hasLength(1),
    );
    expect(
      await db.customSelect('SELECT id FROM publish_queue').get(),
      hasLength(1),
    );
  });
}
