import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

BlogModel _blog(String id, {String content = 'body'}) => BlogModel(
  id: id,
  title: 'title $id',
  content: content,
  posterId: 'poster',
  imageUrl: '',
  tags: const ['诗歌'],
  updatedAt: DateTime.utc(2024),
);

void main() {
  test('each content language has its own cache rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final content = ContentLocale();
    final cache = SqliteBlogCache(db, contentLocale: content);

    await cache.uploadLocalBlogs(blogs: [_blog('shared', content: '中文正文')]);
    expect((await cache.loadBlogs()).single.content, '中文正文');
    expect((await cache.loadBlogById('shared'))?.content, '中文正文');

    content.update(ContentLanguage.en);
    // The other language starts empty: it must not look at the Chinese rows,
    // and the empty result is a per-language cache miss, not "no articles".
    expect(await cache.loadBlogs(), isEmpty);
    expect(await cache.loadBlogById('shared'), isNull);
    expect(await cache.searchLocalBlogs('title'), isEmpty);

    await cache.uploadLocalBlogs(blogs: [_blog('shared', content: 'english')]);
    expect((await cache.loadBlogs()).single.content, 'english');
    expect(await cache.loadBlogs(), hasLength(1));

    // Switching back still sees the Chinese row untouched, next to the same
    // slug in the other language.
    content.update(ContentLanguage.zh);
    expect((await cache.loadBlogs()).single.content, '中文正文');
    expect(await cache.loadBlogs(), hasLength(1), reason: 'one row per language');

    // The server copy is gone, so every language drops it: a deleted article
    // must not reappear offline in the other language.
    await cache.deleteCachedBlog('shared');
    expect(await cache.loadBlogs(), isEmpty);
    content.update(ContentLanguage.en);
    expect(await cache.loadBlogs(), isEmpty);
  });
}
