import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:drift/drift.dart';

class SqliteBlogDraftStore implements BlogDraftStore {
  final AppDatabase database;
  SqliteBlogDraftStore(this.database);

  @override
  Future<BlogDraft?> load(String? blogId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM drafts WHERE blog_id IS ? ORDER BY updated_at DESC, id DESC LIMIT 1',
          variables: [Variable<String>(blogId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return BlogDraft(
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
  Future<void> save(BlogDraft draft) async {
    await database.transaction(() async {
      final existing = await load(draft.blogId);
      if (existing != null) {
        draft.id = existing.id;
        await database.customStatement(
          'UPDATE drafts SET title = ?, content = ?, tags = ?, updated_at = ? WHERE id = ?',
          [
            draft.title,
            draft.content,
            jsonEncode(draft.tags),
            draft.updatedAt.microsecondsSinceEpoch,
            draft.id,
          ],
        );
      } else {
        final id = await database.customInsert(
          'INSERT INTO drafts(blog_id, title, content, tags, updated_at) VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable<String>(draft.blogId),
            Variable(draft.title),
            Variable(draft.content),
            Variable(jsonEncode(draft.tags)),
            Variable(draft.updatedAt.microsecondsSinceEpoch),
          ],
        );
        draft.id = id;
      }
    });
  }

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async {
    final deleted = await database.customUpdate(
      'DELETE FROM drafts WHERE id = ? AND blog_id IS ? AND updated_at = ?',
      variables: [
        Variable(draft.id),
        Variable<String>(draft.blogId),
        Variable(draft.updatedAt.microsecondsSinceEpoch),
      ],
    );
    return deleted == 1;
  }

  @override
  Future<int> deleteDraftsFor(String? blogId, {DateTime? olderThan}) async {
    if (olderThan == null) {
      return database.customUpdate(
        'DELETE FROM drafts WHERE blog_id IS ?',
        variables: [Variable<String>(blogId)],
      );
    }
    return database.customUpdate(
      'DELETE FROM drafts WHERE blog_id IS ? AND updated_at <= ?',
      variables: [
        Variable<String>(blogId),
        Variable<int>(olderThan.microsecondsSinceEpoch),
      ],
    );
  }
}
