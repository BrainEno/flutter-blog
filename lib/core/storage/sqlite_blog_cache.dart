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

  Future<List<BlogModel>> _load(String? query) async {
    // instr treats %, _ and backslashes as literal characters, not SQL wildcards.
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE ? IS NULL OR instr(lower(title), lower(?)) > 0 ORDER BY updated_at DESC, id ASC LIMIT 500',
          variables: [Variable<String>(query), Variable<String>(query)],
        )
        .get();
    return rows
        .map(
          (row) => BlogModel(
            id: row.read<String>('id'),
            title: row.read<String>('title'),
            content: row.read<String>('content'),
            posterId: row.read<String>('poster_id'),
            imageUrl: row.read<String>('image_url'),
            tags: (jsonDecode(row.read<String>('tags')) as List).cast<String>(),
            updatedAt: DateTime.fromMicrosecondsSinceEpoch(
              row.read<int>('updated_at'),
            ),
            posterName: row.readNullable<String>('poster_name'),
            posterAvatar: row.readNullable<String>('poster_avatar'),
          ),
        )
        .toList();
  }

  @override
  Future<List<BlogModel>> loadBlogs() => _load(null);

  @override
  Future<List<BlogModel>> searchLocalBlogs(String query) => _load(query);
}
