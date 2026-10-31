import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:drift/drift.dart';

class SqliteBlogCache implements BlogLocalDataSource {
  final AppDatabase database;
  SqliteBlogCache(this.database);

  @override
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs}) =>
      database.transaction(() async {
        for (final blog in blogs) {
          await database.upsertBlog(blog);
        }
      });

  @override
  Future<List<BlogModel>> loadBlogs({int limit = 500, int offset = 0}) async {
    RangeError.checkValueInInterval(limit, 1, 500, 'limit');
    RangeError.checkNotNegative(offset, 'offset');
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache ORDER BY updated_at DESC, id ASC LIMIT ? OFFSET ?',
          variables: [Variable<int>(limit), Variable<int>(offset)],
        )
        .get();
    return rows.map((row) => _blogFromRow(row.data)).toList();
  }

  @override
  Future<List<BlogModel>> searchLocalBlogs(String query) async {
    // instr treats %, _ and backslashes as literal characters, not SQL wildcards.
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE instr(lower(title), lower(?)) > 0 ORDER BY updated_at DESC, id ASC LIMIT 500',
          variables: [Variable<String>(query)],
        )
        .get();
    return rows.map((row) => _blogFromRow(row.data)).toList();
  }

  @override
  Future<void> deleteCachedBlog(String id) => database.deleteBlogCacheRow(id);

  @override
  Future<BlogModel?> loadBlogById(String id) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE id = ? LIMIT 1',
          variables: [Variable<String>(id)],
        )
        .get();
    return rows.isEmpty ? null : _blogFromRow(rows.single.data);
  }

  BlogModel _blogFromRow(Map<String, Object?> data) {
    return BlogModel(
      id: data['id']! as String,
      articleId: data['article_id'] as String? ?? '',
      title: data['title']! as String,
      content: data['content']! as String,
      posterId: data['poster_id']! as String,
      imageUrl: data['image_url']! as String,
      tags: (jsonDecode(data['tags']! as String) as List).cast<String>(),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        data['updated_at']! as int,
      ),
      posterName: data['poster_name'] as String?,
      posterAvatar: data['poster_avatar'] as String?,
    );
  }
}
