import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:drift/drift.dart';

/// Account-scoped drafts. The old `drafts` table is deliberately never read
/// for an account: neither SQLite nor the older Isar schema recorded an owner.
class SqliteBlogDraftStore implements BlogDraftStore {
  SqliteBlogDraftStore(this.database, {required Uri apiBaseUrl})
    : _backend = _backendKey(apiBaseUrl);

  final AppDatabase database;
  final String _backend;
  Future<void> _writeTail = Future<void>.value();

  /// Use the same base-path convention as the API client. Do not persist
  /// URL user-info, query strings or fragments as part of the namespace.
  static String _backendKey(Uri uri) {
    if (!uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError('A valid HTTP(S) API base URL is required.');
    }
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  static void _requireUserId(String userId) {
    if (userId.isEmpty || userId != userId.trim()) {
      throw ArgumentError('A non-empty, unmodified account id is required.');
    }
  }

  /// Order all mutations made through this store, even if an earlier write
  /// fails. A publish cleanup cannot overtake a pending auto-save, and a
  /// newly opened editor's load waits for earlier saves from the old editor.
  Future<T> _serializeWrite<T>(Future<T> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  @override
  Future<BlogDraft?> load(String? blogId, {required String userId}) async {
    _requireUserId(userId);
    await _writeTail;
    return _load(blogId, userId);
  }

  Future<BlogDraft?> _load(String? blogId, String userId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM account_drafts '
          'WHERE backend = ? AND user_id = ? AND blog_id IS ? LIMIT 1',
          variables: [
            Variable<String>(_backend),
            Variable<String>(userId),
            Variable<String>(blogId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return BlogDraft(
      userId: row.read<String>('user_id'),
      blogId: row.readNullable<String>('blog_id'),
      title: row.read<String>('title'),
      content: row.read<String>('content'),
      tags: (jsonDecode(row.read<String>('tags')) as List).cast<String>(),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row.read<int>('updated_at'),
      ),
    )..id = row.read<int>('id');
  }

  @override
  Future<void> save(BlogDraft draft) {
    _requireUserId(draft.userId);
    // Capture the mutable tag list before this write waits for its turn.
    final tags = jsonEncode(draft.tags);
    return _serializeWrite(() async {
      await database.transaction(() async {
        final existing = await _load(draft.blogId, draft.userId);
        if (existing != null) {
          draft.id = existing.id;
          await database.customStatement(
            'UPDATE account_drafts SET title = ?, content = ?, tags = ?, updated_at = ? '
            'WHERE id = ? AND backend = ? AND user_id = ? AND blog_id IS ?',
            [
              draft.title,
              draft.content,
              tags,
              draft.updatedAt.microsecondsSinceEpoch,
              draft.id,
              _backend,
              draft.userId,
              draft.blogId,
            ],
          );
        } else {
          final id = await database.customInsert(
            'INSERT INTO account_drafts(backend, user_id, blog_id, title, content, tags, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            variables: [
              Variable<String>(_backend),
              Variable<String>(draft.userId),
              Variable<String>(draft.blogId),
              Variable(draft.title),
              Variable(draft.content),
              Variable(tags),
              Variable(draft.updatedAt.microsecondsSinceEpoch),
            ],
          );
          draft.id = id;
        }
      });
    });
  }

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) {
    _requireUserId(draft.userId);
    final id = draft.id;
    return _serializeWrite(() async {
      final deleted = await database.customUpdate(
        'DELETE FROM account_drafts '
        'WHERE id = ? AND backend = ? AND user_id = ? AND blog_id IS ? '
        'AND updated_at = ? AND title = ? AND content = ? AND tags = ?',
        variables: [
          Variable(id),
          Variable<String>(_backend),
          Variable<String>(draft.userId),
          Variable<String>(draft.blogId),
          Variable<int>(draft.updatedAt.microsecondsSinceEpoch),
          Variable<String>(draft.title),
          Variable<String>(draft.content),
          Variable<String>(jsonEncode(draft.tags)),
        ],
      );
      return deleted == 1;
    });
  }

  @override
  Future<bool> hasUnclaimedDrafts() async {
    final rows = await database
        .customSelect('SELECT 1 FROM drafts LIMIT 1')
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<int> deleteDraftsFor(
    String? blogId, {
    required String userId,
    DateTime? olderThan,
  }) {
    _requireUserId(userId);
    return _serializeWrite(() {
      if (olderThan == null) {
        return database.customUpdate(
          'DELETE FROM account_drafts WHERE backend = ? AND user_id = ? AND blog_id IS ?',
          variables: [
            Variable<String>(_backend),
            Variable<String>(userId),
            Variable<String>(blogId),
          ],
        );
      }
      return database.customUpdate(
        'DELETE FROM account_drafts WHERE backend = ? AND user_id = ? AND blog_id IS ? AND updated_at < ?',
        variables: [
          Variable<String>(_backend),
          Variable<String>(userId),
          Variable<String>(blogId),
          Variable<int>(olderThan.microsecondsSinceEpoch),
        ],
      );
    });
  }
}
