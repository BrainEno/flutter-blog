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
  int get schemaVersion => 15;

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
      await _createStructuredBodyDrafts();
      await _createBlogCache();
      await _createBlogCacheFeedIndex();
      await _createReadingHistory();
      await _createPublishQueue();
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
        // v4 added only an index. The v7 step below rebuilds the table and
        // recreates the index over the new (id, content_locale) key, and a
        // pre-v7 table has no `content_locale` column to index yet, so there
        // is nothing to do here.
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
      if (from < 7) {
        // v7 makes the content language part of the cache identity (#108):
        // one slug can be cached in Chinese and in English, and a row written
        // for one language must never be served for the other. Every earlier
        // build requested zh-CN, so existing rows are Chinese.
        if (await _tableExists('blog_cache')) {
          await customStatement(
            'ALTER TABLE blog_cache RENAME TO blog_cache_v6',
          );
          await _createBlogCache();
          await customStatement(
            'INSERT INTO blog_cache (id, article_id, title, content, poster_id, '
            'image_url, tags, updated_at, poster_name, poster_avatar, '
            'document_json, content_locale) '
            'SELECT id, article_id, title, content, poster_id, image_url, tags, '
            'updated_at, poster_name, poster_avatar, document_json, \'zh-CN\' '
            'FROM blog_cache_v6',
          );
          await customStatement('DROP TABLE blog_cache_v6');
        } else {
          // A database that never held a cache still has to leave this step
          // with the v7 table: the app reads it unconditionally afterwards.
          await _createBlogCache();
        }
        await _createBlogCacheFeedIndex();
      }
      if (from < 8) {
        // v8 adds the publish queue (issue #23): the durable record of a
        // publish the server has not accepted yet. Pure addition - no existing
        // table is touched, and an empty queue behaves exactly like before.
        await _createPublishQueue();
      }
      if (from < 9) {
        // v9 remembers the cover a queued send already uploaded, so a retry
        // reuses that URL instead of sending the bytes again and leaving an
        // unreferenced asset behind. Existing rows get NULL, which reads as
        // "not uploaded yet" - exactly what v8 did on every attempt.
        //
        // Both checks matter: a database older than v8 got the table from the
        // step above, already in its v9 shape, and must not be altered again.
        if (!await _tableExists('publish_queue')) {
          await _createPublishQueue();
        } else if (!await _columnExists('publish_queue', 'cover_url')) {
          await customStatement(
            'ALTER TABLE publish_queue ADD COLUMN cover_url TEXT',
          );
        }
      }
      if (from < 10) {
        // v10 lets the queue carry edits of published articles, not just new
        // ones: `kind` says which, `target_id` is the article an edit updates.
        // Existing rows are creates, which is what they were.
        if (!await _tableExists('publish_queue')) {
          await _createPublishQueue();
        } else {
          if (!await _columnExists('publish_queue', 'kind')) {
            await customStatement(
              "ALTER TABLE publish_queue ADD COLUMN kind TEXT NOT NULL "
              "DEFAULT 'create'",
            );
          }
          if (!await _columnExists('publish_queue', 'target_id')) {
            await customStatement(
              'ALTER TABLE publish_queue ADD COLUMN target_id TEXT',
            );
          }
        }
      }
      if (from < 11) {
        // v11 records the language edition a queued edit writes. An article id
        // is a work, and `(id, locale)` is one translation of it, so a replay
        // without the edition would rewrite whichever language the app
        // displayed at retry time. Existing rows get NULL, which reads as
        // "use the content language in effect" - exactly what v10 did.
        if (!await _tableExists('publish_queue')) {
          await _createPublishQueue();
        } else if (!await _columnExists('publish_queue', 'locale')) {
          await customStatement(
            'ALTER TABLE publish_queue ADD COLUMN locale TEXT',
          );
        }
      }
      if (from < 12) {
        // v12 records the category an author picked in the editor. Categories
        // are editorial structure (ADR 0016), so the app can only choose among
        // existing ones - and it has to remember the choice across a draft, an
        // offline queue entry and a relaunch, or a queued publish arrives
        // without it. NULL means "the author never touched the picker", which
        // is not the same as "no category": the write omits the field and the
        // server keeps whatever the article already had.
        if (!await _tableExists('account_drafts')) {
          await _createAccountDrafts();
        } else if (!await _columnExists('account_drafts', 'category_ids')) {
          await customStatement(
            'ALTER TABLE account_drafts ADD COLUMN category_ids TEXT',
          );
        }
        if (!await _tableExists('publish_queue')) {
          await _createPublishQueue();
        } else if (!await _columnExists('publish_queue', 'category_ids')) {
          await customStatement(
            'ALTER TABLE publish_queue ADD COLUMN category_ids TEXT',
          );
        }
      }
      if (from < 13) {
        // v13 keeps the categories an article was filed under, with the names
        // the server rendered for this edition. They used to be dropped at the
        // cache boundary, so an offline article showed its tags and author but
        // not where it sits. NULL means the row predates this column: no chip
        // is drawn rather than an empty one that would claim "none".
        if (!await _tableExists('blog_cache')) {
          await _createBlogCache();
          await _createBlogCacheFeedIndex();
        } else if (!await _columnExists('blog_cache', 'categories_json')) {
          await customStatement(
            'ALTER TABLE blog_cache ADD COLUMN categories_json TEXT',
          );
        }
      }
      if (from < 14) {
        // Rich-body recovery is separate from the existing plain editor. Do
        // not infer owners, editions or source bodies from old text drafts.
        await _createStructuredBodyDrafts();
      }
      if (from < 15) {
        // v14 only retained bodies. NULL records that metadata was never saved;
        // it must not be reconstructed from a flat draft or assumed empty.
        if (!await _columnExists('structured_body_drafts', 'base_metadata')) {
          await customStatement(
            'ALTER TABLE structured_body_drafts ADD COLUMN base_metadata TEXT',
          );
        }
        if (!await _columnExists(
          'structured_body_drafts',
          'session_metadata',
        )) {
          await customStatement(
            'ALTER TABLE structured_body_drafts ADD COLUMN session_metadata TEXT',
          );
        }
      }
    },
  );

  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  /// New drafts are separate from the unattributed legacy table. Partial
  /// unique indexes include the null new-article key as well as article ids.
  Future<void> _createAccountDrafts() async {
    await customStatement(
      'CREATE TABLE account_drafts ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, backend TEXT NOT NULL, '
      'user_id TEXT NOT NULL, blog_id TEXT, title TEXT NOT NULL, '
      'content TEXT NOT NULL, tags TEXT NOT NULL, category_ids TEXT, '
      'updated_at INTEGER NOT NULL)',
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

  /// A body recovery snapshot is keyed by backend, account, server article
  /// identity and edition. The row id and revision are local compare-and-swap
  /// tokens; they are not server versions and never authorize a remote write.
  Future<void> _createStructuredBodyDrafts() => customStatement(
    'CREATE TABLE structured_body_drafts ('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, backend TEXT NOT NULL, '
    'user_id TEXT NOT NULL, article_id TEXT NOT NULL, locale TEXT NOT NULL, '
    'revision INTEGER NOT NULL, base_version INTEGER NOT NULL, '
    'base_blocks TEXT NOT NULL, body_version INTEGER NOT NULL, '
    'body_blocks TEXT NOT NULL, updated_at INTEGER NOT NULL, '
    'base_metadata TEXT, session_metadata TEXT, '
    'UNIQUE(backend, user_id, article_id, locale))',
  );

  /// Publishes waiting for the server (issue #23).
  ///
  /// `backend` and `user_id` fence an entry to the API origin and the account
  /// that queued it; `idempotency_key` is sent on every attempt so a retry
  /// replays the article the server may already have created. `cover_file` is
  /// a file name inside the app's own `publish_queue/` directory, never the
  /// picker's temporary path; `cover_url` is where an earlier attempt uploaded
  /// those bytes, so a retry reuses the asset instead of uploading it again.
  /// `kind` separates a new article from an edit of an existing one, whose
  /// public id is `target_id`; `locale` is the language edition an edit
  /// writes, so a retry cannot rewrite a different translation.
  Future<void> _createPublishQueue() async {
    await customStatement(
      'CREATE TABLE publish_queue ('
      'id TEXT PRIMARY KEY, backend TEXT NOT NULL, user_id TEXT NOT NULL, '
      'idempotency_key TEXT NOT NULL, title TEXT NOT NULL, '
      'content TEXT NOT NULL, tags TEXT NOT NULL, cover_file TEXT, '
      'cover_mime TEXT, cover_url TEXT, '
      "kind TEXT NOT NULL DEFAULT 'create', target_id TEXT, locale TEXT, "
      'category_ids TEXT, state TEXT NOT NULL, '
      'attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER, '
      'last_error_code TEXT, '
      'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX publish_queue_due '
      'ON publish_queue(backend, user_id, state, created_at)',
    );
  }

  /// The offline blog cache. `id` is the article's public slug on the
  /// no-wave backend; `article_id` is the server UUID needed for writes;
  /// `content_locale` is the language the body was fetched in, and is part of
  /// the key so both languages can be cached side by side (#108).
  Future<void> _createBlogCache() => customStatement(
    'CREATE TABLE blog_cache (id TEXT NOT NULL, content_locale TEXT NOT NULL DEFAULT \'zh-CN\', article_id TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL, content TEXT NOT NULL, poster_id TEXT NOT NULL, image_url TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL, poster_name TEXT, poster_avatar TEXT, document_json TEXT, categories_json TEXT, PRIMARY KEY (id, content_locale))',
  );

  /// Supports stable, per-language feed pagination without sorting all cached
  /// article bodies.
  Future<void> _createBlogCacheFeedIndex() => customStatement(
    'CREATE INDEX blog_cache_feed_order ON blog_cache(content_locale, updated_at DESC, id ASC)',
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

  /// Drops every cached language of one article.
  ///
  /// The article itself is gone on the server, so no language may keep a copy
  /// (a deleted article must not reappear offline in the other language).
  Future<void> deleteBlogCacheRow(String id) =>
      customStatement('DELETE FROM blog_cache WHERE id = ?', [id]);

  /// Writes one cached article row from primitives.
  ///
  /// The mapping to and from the feature's article model lives with the cache
  /// adapter in that feature, so storage never imports it (#107).
  Future<void> upsertBlogRow({
    required String id,
    required String contentLocale,
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
    String? categoriesJson,
  }) => customStatement(
    '''
    INSERT INTO blog_cache(id, content_locale, article_id, title, content, poster_id, image_url, tags, updated_at, poster_name, poster_avatar, document_json, categories_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id, content_locale) DO UPDATE SET article_id = excluded.article_id, title = excluded.title, content = excluded.content,
      poster_id = excluded.poster_id, image_url = excluded.image_url, tags = excluded.tags,
      updated_at = excluded.updated_at, poster_name = excluded.poster_name, poster_avatar = excluded.poster_avatar,
      document_json = excluded.document_json, categories_json = excluded.categories_json
    ''',
    [
      id,
      contentLocale,
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
      categoriesJson,
    ],
  );
}
