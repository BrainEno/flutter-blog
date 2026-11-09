import 'dart:convert';

import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/article_document_codec.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:drift/drift.dart';

/// The offline cache is scoped by content language (#108): rows written for
/// one language are invisible to the other, so switching languages can neither
/// surface the wrong language nor make another language's cached list look
/// like "no articles" - each language has its own list.
class SqliteBlogCache implements BlogLocalDataSource {
  final AppDatabase database;

  /// Null keeps the default instance, which is the historical Chinese cache.
  final ContentLocale? contentLocale;

  SqliteBlogCache(this.database, {this.contentLocale});

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  @override
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs}) {
    final locale = _locale;
    return database.transaction(() async {
      for (final blog in blogs) {
        await database.upsertBlogRow(
          id: blog.id,
          contentLocale: locale,
          articleId: blog.articleId,
          title: blog.title,
          content: blog.content,
          posterId: blog.posterId,
          imageUrl: blog.imageUrl,
          tags: blog.tags,
          updatedAt: blog.updatedAt,
          posterName: blog.posterName,
          posterAvatar: blog.posterAvatar,
          documentJson: blog.documentJson,
          categoriesJson: _encodeCategories(blog.categories),
        );
      }
    });
  }

  @override
  Future<List<BlogModel>> loadBlogs({int limit = 500, int offset = 0}) async {
    RangeError.checkValueInInterval(limit, 1, 500, 'limit');
    RangeError.checkNotNegative(offset, 'offset');
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE content_locale = ? '
          'ORDER BY updated_at DESC, id ASC LIMIT ? OFFSET ?',
          variables: [
            Variable<String>(_locale),
            Variable<int>(limit),
            Variable<int>(offset),
          ],
        )
        .get();
    return rows.map((row) => _blogFromRow(row.data)).toList();
  }

  @override
  Future<List<BlogModel>> searchLocalBlogs(String query) async {
    // instr treats %, _ and backslashes as literal characters, not SQL wildcards.
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE content_locale = ? '
          'AND instr(lower(title), lower(?)) > 0 '
          'ORDER BY updated_at DESC, id ASC LIMIT 500',
          variables: [Variable<String>(_locale), Variable<String>(query)],
        )
        .get();
    return rows.map((row) => _blogFromRow(row.data)).toList();
  }

  /// Removes the article in every cached language: the server copy is gone,
  /// so no language may serve it offline.
  @override
  Future<void> deleteCachedBlog(String id) => database.deleteBlogCacheRow(id);

  @override
  Future<BlogModel?> loadBlogById(String id) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE id = ? AND content_locale = ? LIMIT 1',
          variables: [Variable<String>(id), Variable<String>(_locale)],
        )
        .get();
    return rows.isEmpty ? null : _blogFromRow(rows.single.data);
  }

  BlogModel _blogFromRow(Map<String, Object?> data) {
    return BlogModel(
      id: data['id']! as String,
      articleId: data['article_id'] as String? ?? '',
      documentJson: data['document_json'] as String?,
      document: decodeCachedArticleDocument(data['document_json'] as String?),
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
      // The row was fetched in this language, so the body is that edition.
      locale: data['content_locale'] as String? ?? '',
      categories: _decodeCategories(data['categories_json'] as String?),
    );
  }

  /// The categories as the JSON array a row keeps.
  ///
  /// An article with none stores `[]`, because that is what the server said.
  /// NULL is reserved for rows written before the column existed, so the two
  /// never have to be guessed apart later.
  String _encodeCategories(List<CategoryRef> categories) => jsonEncode([
    for (final category in categories)
      {
        'id': category.id,
        'slug': category.slug,
        'name': category.name,
        'description': category.description,
      },
  ]);

  /// Reads the column back. A row that predates the column has no categories
  /// to show; damaged JSON is treated the same way rather than failing a whole
  /// offline list over one label.
  List<CategoryRef> _decodeCategories(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final value in decoded)
          if (value is Map)
            CategoryRef(
              id: value['id'] as String? ?? '',
              slug: value['slug'] as String? ?? '',
              name: value['name'] as String? ?? '',
              description: value['description'] as String? ?? '',
            ),
      ];
    } on FormatException {
      return const [];
    }
  }
}
