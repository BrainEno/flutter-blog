import 'dart:convert';

import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/data/datasources/article_document_codec.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:drift/drift.dart';

/// The offline cache is scoped by content language (#108): rows written for
/// one language are invisible to the other, so switching languages can neither
/// surface the wrong language nor make another language's cached list look
/// like "no articles" - each language has its own list.
class SqliteBlogCache implements BlogLocalDataSource {
  final AppDatabase database;

  /// Null keeps the default instance, which is the historical Chinese cache.
  final ContentLocale? contentLocale;

  SqliteBlogCache(
    this.database, {
    required Uri apiBaseUrl,
    this.contentLocale,
    DateTime Function()? now,
  }) : _backend = backendKeyOf(apiBaseUrl),
       _now = now ?? DateTime.now;

  final String _backend;
  final DateTime Function() _now;
  static const int maxEntriesPerLocale = 250;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  @override
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs}) {
    final locale = _locale;
    return database.transaction(() async {
      for (final blog in blogs) {
        await database.upsertBlogRow(
          id: blog.id,
          contentLocale: locale,
          backend: _backend,
          accessedAt: _now().toUtc().microsecondsSinceEpoch,
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
          articleRevision: blog.articleRevision?.value,
        );
      }
      await database.customStatement(
        'DELETE FROM blog_cache WHERE backend = ? AND content_locale = ? AND id IN ('
        'SELECT id FROM blog_cache WHERE backend = ? AND content_locale = ? '
        'ORDER BY accessed_at DESC, id ASC LIMIT -1 OFFSET ?)',
        [_backend, locale, _backend, locale, maxEntriesPerLocale],
      );
    });
  }

  /// Update the LRU order for the exact rows returned by this backend and
  /// locale. A single bounded statement avoids a write per result.
  Future<void> _touch(String locale, List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    try {
      await database.customStatement(
        'UPDATE blog_cache SET accessed_at = ? WHERE backend = ? '
        'AND content_locale = ? AND id IN ($placeholders)',
        [_now().toUtc().microsecondsSinceEpoch, _backend, locale, ...ids],
      );
    } on Object {
      // A failed advisory touch must not make already-read offline content
      // unavailable (for example when the disk is full). The next successful
      // eviction may treat this item as older than it actually is.
    }
  }

  @override
  Future<List<BlogModel>> loadBlogs({int limit = 500, int offset = 0}) async {
    RangeError.checkValueInInterval(limit, 1, 500, 'limit');
    RangeError.checkNotNegative(offset, 'offset');
    final locale = _locale;
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE backend = ? AND content_locale = ? '
          'ORDER BY updated_at DESC, id ASC LIMIT ? OFFSET ?',
          variables: [
            Variable<String>(_backend),
            Variable<String>(locale),
            Variable<int>(limit),
            Variable<int>(offset),
          ],
        )
        .get();
    final blogs = rows.map((row) => _blogFromRow(row.data)).toList();
    await _touch(locale, blogs.map((blog) => blog.id).toList());
    return blogs;
  }

  @override
  Future<List<BlogModel>> searchLocalBlogs(String query) async {
    // instr treats %, _ and backslashes as literal characters, not SQL wildcards.
    final locale = _locale;
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE backend = ? AND content_locale = ? '
          'AND instr(lower(title), lower(?)) > 0 '
          'ORDER BY updated_at DESC, id ASC LIMIT 500',
          variables: [
            Variable<String>(_backend),
            Variable<String>(locale),
            Variable<String>(query),
          ],
        )
        .get();
    final blogs = rows.map((row) => _blogFromRow(row.data)).toList();
    await _touch(locale, blogs.map((blog) => blog.id).toList());
    return blogs;
  }

  @override
  Future<OfflineLibrarySnapshot> inspectOfflineLibrary() async {
    final locale = _locale;
    // This intentionally stays a bounded table scan. The cache already has a
    // strict per-backend/per-locale cap, and maintaining a shadow FTS table
    // would create another write consistency path for every cache update.
    final rows = await database
        .customSelect(
          'SELECT *, ($_estimatedRowBytes) AS estimated_bytes '
          'FROM blog_cache WHERE backend = ? AND content_locale = ? '
          'ORDER BY accessed_at DESC, updated_at DESC, id ASC '
          'LIMIT ?',
          variables: [
            Variable<String>(_backend),
            Variable<String>(locale),
            Variable<int>(maxEntriesPerLocale),
          ],
        )
        .get();
    final summaryRow = await database
        .customSelect(
          'SELECT COUNT(*) AS article_count, '
          'COALESCE(SUM($_estimatedRowBytes), 0) AS estimated_bytes, '
          'MAX(accessed_at) AS newest_accessed_at '
          'FROM blog_cache WHERE backend = ? AND content_locale = ?',
          variables: [Variable<String>(_backend), Variable<String>(locale)],
        )
        .getSingle();
    final summary = OfflineLibrarySummary(
      articleCount: summaryRow.read<int>('article_count'),
      estimatedBytes: summaryRow.read<int>('estimated_bytes'),
      newestAccessedAt: _microsecondsOrNull(
        summaryRow.data['newest_accessed_at'] as int?,
      ),
    );
    return OfflineLibrarySnapshot(
      locale: locale,
      summary: summary,
      entries: [
        for (final row in rows)
          OfflineLibraryEntry(
            article: _blogFromRow(row.data),
            lastAccessedAt:
                _microsecondsOrNull(row.data['accessed_at'] as int?) ??
                DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
            estimatedBytes: row.read<int>('estimated_bytes'),
          ),
      ],
    );
  }

  /// SQLite [length] counts Unicode characters for TEXT. Casting values to BLOB
  /// makes this a UTF-8 byte estimate and includes only values owned by this
  /// one cache row, not SQLite/WAL overhead or image-package disk files.
  static const String _estimatedRowBytes =
      "length(CAST(backend AS BLOB)) + length(CAST(id AS BLOB)) + "
      "length(CAST(content_locale AS BLOB)) + length(CAST(article_id AS BLOB)) + "
      "length(CAST(title AS BLOB)) + "
      "length(CAST(content AS BLOB)) + length(CAST(poster_id AS BLOB)) + "
      "length(CAST(image_url AS BLOB)) + length(CAST(tags AS BLOB)) + "
      "length(CAST(COALESCE(poster_name, '') AS BLOB)) + "
      "length(CAST(COALESCE(poster_avatar, '') AS BLOB)) + "
      "length(CAST(COALESCE(document_json, '') AS BLOB)) + "
      "length(CAST(COALESCE(categories_json, '') AS BLOB))";

  DateTime? _microsecondsOrNull(int? value) {
    if (value == null || value <= 0) return null;
    return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
  }

  @override
  Future<void> clearOfflineLibrary() {
    final locale = _locale;
    return database.customStatement(
      'DELETE FROM blog_cache WHERE backend = ? AND content_locale = ?',
      [_backend, locale],
    );
  }

  /// Removes the article in every cached language: the server copy is gone,
  /// so no language may serve it offline.
  @override
  Future<void> deleteCachedBlog(String id) =>
      database.deleteBlogCacheRow(id, backend: _backend);

  @override
  Future<BlogModel?> loadBlogById(String id) async {
    final locale = _locale;
    final rows = await database
        .customSelect(
          'SELECT * FROM blog_cache WHERE backend = ? AND id = ? AND content_locale = ? LIMIT 1',
          variables: [
            Variable<String>(_backend),
            Variable<String>(id),
            Variable<String>(locale),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final blog = _blogFromRow(rows.single.data);
    await _touch(locale, [blog.id]);
    return blog;
  }

  BlogModel _blogFromRow(Map<String, Object?> data) {
    return BlogModel(
      id: data['id']! as String,
      articleId: data['article_id'] as String? ?? '',
      // Old rows and corrupt values both become unavailable conditions. An
      // editor then retains its text and refuses the unconditional legacy PUT.
      articleRevision: ArticleRevision.parse(data['article_revision']),
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
