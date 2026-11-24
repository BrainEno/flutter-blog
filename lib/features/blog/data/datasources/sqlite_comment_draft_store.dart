import 'dart:convert';

import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/domain/repositories/comment_draft_store.dart';

/// [CommentDraftStore] in the app's `metadata` key/value table: one JSON list
/// per backend and account, newest first and capped at
/// [AppLimits.commentDrafts], so the feature needs no schema migration and
/// abandoned drafts cannot pile up.
///
/// Every write reads, changes and writes that one list, so writes run one
/// after another: two articles saving at once must not drop each other's
/// draft.
class SqliteCommentDraftStore implements CommentDraftStore {
  SqliteCommentDraftStore(this.database, {required Uri apiBaseUrl})
    : _backend = backendKeyOf(apiBaseUrl);

  final AppDatabase database;
  final String _backend;
  Future<void> _writes = Future<void>.value();

  /// The metadata key of [userId]'s drafts. JSON-encoded so neither part can
  /// run into the other, whatever characters they hold.
  String keyFor(String userId) =>
      'comment_drafts:${jsonEncode([_backend, userId])}';

  @override
  Future<CommentDraft?> load({
    required String userId,
    required String slug,
  }) async {
    // A read waits for the writes before it, so it never sees an older
    // draft than one already handed to [save].
    await _writes;
    for (final entry in await _entries(userId)) {
      if (entry.slug == slug) return entry.draft;
    }
    return null;
  }

  @override
  Future<void> save({
    required String userId,
    required String slug,
    required CommentDraft draft,
  }) {
    final write = _writes.then((_) => _write(userId, slug, draft));
    // A failed write is the caller's to hear about; the next one still runs.
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _write(String userId, String slug, CommentDraft draft) async {
    final others = [
      for (final entry in await _entries(userId))
        if (entry.slug != slug) entry,
    ];
    final entries = [
      if (!draft.isBlank) _Entry(slug, draft),
      ...others,
    ].take(AppLimits.commentDrafts).toList();
    final key = keyFor(userId);
    if (entries.isEmpty) return database.deleteMetadata(key);
    return database.writeMetadata(
      key,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
  }

  Future<List<_Entry>> _entries(String userId) async {
    final raw = await database.readMetadata(keyFor(userId));
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final entries = <_Entry>[];
    final seen = <String>{};
    for (final item in decoded) {
      final entry = _Entry.fromJson(item);
      // A damaged or repeated row is skipped, never allowed to hide the
      // rest of the list.
      if (entry != null && seen.add(entry.slug)) entries.add(entry);
    }
    return entries;
  }
}

class _Entry {
  const _Entry(this.slug, this.draft);

  final String slug;
  final CommentDraft draft;

  static _Entry? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final slug = json['slug'];
    final text = json['text'];
    final parent = json['parent'];
    final parentAuthor = json['parentAuthor'];
    if (slug is! String || slug.isEmpty || text is! String) return null;
    final draft = CommentDraft(
      text: text,
      parentCommentId: parent is String && parent.isNotEmpty ? parent : null,
      parentAuthorName: parentAuthor is String ? parentAuthor : '',
    );
    return draft.isBlank ? null : _Entry(slug, draft);
  }

  Map<String, Object?> toJson() => {
    'slug': slug,
    'text': draft.text,
    'parent': ?draft.parentCommentId,
    if (draft.parentAuthorName.isNotEmpty)
      'parentAuthor': draft.parentAuthorName,
  };
}
