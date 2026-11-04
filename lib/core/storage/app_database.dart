import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// The single SQLite store: tables, migrations and primitive row access.
///
/// Isar is gone since #107 retired the one-time importer; nothing in the app
/// depends on an unmaintained database engine any more.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 6;

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
      await _createAccountDrafts();
      await _createBlogCache();
      await _createBlogCacheFeedIndex();
      await _createReadingHistory();
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
      if (from < 3) {
        // v3 adds the device-local reading history (issue #22). Pure
        // addition: no existing table is touched.
        await _createReadingHistory();
      }
      if (from < 4) {
        // v4 adds only an index; cached articles and all other data stay put.
        await _createBlogCacheFeedIndex();
      }
      if (from < 5) {
        // Earlier no-wave cache rows already flattened the document, so we
        // cannot know whether formatting or images were lost. Mark them as
        // potentially incomplete until refreshed, without changing content.
        // Pre-no-wave/Isar rows without a server article id remain Markdown.
        await customStatement(
          'ALTER TABLE blog_cache ADD COLUMN document_json TEXT',
        );
        await customStatement(
          '''UPDATE blog_cache SET document_json = '{"version":null,"blocks":[]}' WHERE length(article_id) > 0''',
        );
      }
      if (from < 6) {
        // Pre-v6 drafts have no provable owner. Keep the old table intact,
        // but never read or assign those rows as any signed-in user's drafts.
        await _createAccountDrafts();
      }
    },
  );

  /// New drafts are separate from the unattributed legacy table. Partial
  /// unique indexes include the null new-article key as well as article ids.
  Future<void> _createAccountDrafts() async {
    await customStatement(
      'CREATE TABLE account_drafts ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, backend TEXT NOT NULL, '
      'user_id TEXT NOT NULL, blog_id TEXT, title TEXT NOT NULL, '
      'content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX account_drafts_new '
      'ON account_drafts(backend, user_id) WHERE blog_id IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX account_drafts_article '
      'ON account_drafts(backend, user_id, blog_id) WHERE blog_id IS NOT NULL',
    );
  }

  /// The offline blog cache. `id` is the article's public slug on the
  /// no-wave backend; `article_id` is the server UUID needed for writes.
  Future<void> _createBlogCache() => customStatement(
    'CREATE TABLE blog_cache (id TEXT PRIMARY KEY, article_id TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT, document_json TEXT)',
  );

  /// Supports stable feed pagination without sorting all cached article bodies.
  Future<void> _createBlogCacheFeedIndex() => customStatement(
    'CREATE INDEX blog_cache_feed_order ON blog_cache(updated_at DESC, id ASC)',
  );

  /// Device-local reading history (issue #22), scoped per signed-in
  /// account. `blog_id` is the article's public slug; the display fields
  /// are snapshots taken at read time so the list stays presentable even
  /// after the article is no longer present in the local blog cache.
  Future<void> _createReadingHistory() async {
    await customStatement(
      'CREATE TABLE reading_history ('
      'user_id TEXT NOT NULL, blog_id TEXT NOT NULL, title TEXT NOT NULL, '
      'poster_name TEXT NOT NULL DEFAULT \'\', image_url TEXT NOT NULL DEFAULT \'\', '
      'read_at INTEGER NOT NULL, PRIMARY KEY (user_id, blog_id))',
    );
    await customStatement(
      'CREATE INDEX reading_history_by_user ON reading_history(user_id, read_at DESC)',
    );
  }

  /// Warns once that a retired `default.isar` file exists.
  ///
  /// The Isar reader was removed (#107): the file cannot be imported any more,
  /// and the app never touches or deletes it. Returns true the first time such
  /// a file is seen so the caller can log it; the marker keeps later launches
  /// quiet. Cache rows rebuild from the network, so only drafts and the theme
  /// choice are affected - see docs/sqlite-storage.md.
  Future<bool> takeRetiredIsarNotice(Directory directory) async {
    final marker = await customSelect(
      "SELECT value FROM metadata WHERE key = 'legacy_isar_removed'",
    ).getSingleOrNull();
    if (marker != null) return false;
    if (!await File('${directory.path}/default.isar').exists()) return false;
    await customStatement(
      "INSERT INTO metadata(key, value) VALUES ('legacy_isar_removed', 'notified')",
    );
    return true;
  }

  /// Stores the theme by name. The preference model is the theme layer's
  /// business; storage only keeps the string (#107).
  Future<void> setTheme(String mode) => customStatement(
    'INSERT INTO theme(id, mode) VALUES (0, ?) ON CONFLICT(id) DO UPDATE SET mode = excluded.mode',
    [mode],
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

  /// Writes one cached article row from primitives.
  ///
  /// The mapping to and from the feature's article model lives with the cache
  /// adapter in that feature, so storage never imports it (#107).
  Future<void> upsertBlogRow({
    required String id,
    required String title,
    required String content,
    required String posterId,
    required String imageUrl,
    required List<String> tags,
    required DateTime updatedAt,
    String articleId = '',
    String? posterName,
    String? posterAvatar,
    String? documentJson,
  }) => customStatement(
    '''
    INSERT INTO blog_cache(id, article_id, title, content, poster_id, image_url, tags, updated_at, poster_name, poster_avatar, document_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET article_id = excluded.article_id, title = excluded.title, content = excluded.content,
      poster_id = excluded.poster_id, image_url = excluded.image_url, tags = excluded.tags,
      updated_at = excluded.updated_at, poster_name = excluded.poster_name, poster_avatar = excluded.poster_avatar,
      document_json = excluded.document_json
    ''',
    [
      id,
      articleId,
      title,
      content,
      posterId,
      imageUrl,
      jsonEncode(tags),
      updatedAt.microsecondsSinceEpoch,
      posterName,
      posterAvatar,
      documentJson,
    ],
  );
}
