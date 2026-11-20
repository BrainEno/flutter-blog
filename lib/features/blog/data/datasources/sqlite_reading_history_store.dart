import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:drift/drift.dart';

class SqliteReadingHistoryStore
    implements ReadingHistoryStore, UnattributedHistoryMaintenance {
  final AppDatabase database;
  SqliteReadingHistoryStore(this.database, {required Uri apiBaseUrl})
    : _backend = backendKeyOf(apiBaseUrl);
  final String _backend;

  @override
  Future<void> record({required String userId, required Blog blog}) {
    return database.customStatement(
      'INSERT INTO reading_history(backend, user_id, blog_id, title, poster_name, image_url, read_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(backend, user_id, blog_id) DO UPDATE SET title = excluded.title, '
      'poster_name = excluded.poster_name, image_url = excluded.image_url, '
      'read_at = excluded.read_at',
      [
        _backend,
        userId,
        blog.id,
        blog.title,
        blog.posterName ?? '',
        blog.imageUrl,
        DateTime.now().microsecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = AppLimits.readingHistoryPageSize,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT blog_id, title, poster_name, image_url, read_at '
          'FROM reading_history WHERE backend = ? AND user_id = ? '
          'ORDER BY read_at DESC, blog_id ASC LIMIT ?',
          variables: [
            Variable<String>(_backend),
            Variable<String>(userId),
            Variable<int>(limit),
          ],
        )
        .get();
    return rows
        .map(
          (row) => ReadingHistoryEntry(
            blogId: row.read<String>('blog_id'),
            title: row.read<String>('title'),
            posterName: row.read<String>('poster_name'),
            imageUrl: row.read<String>('image_url'),
            readAt: DateTime.fromMicrosecondsSinceEpoch(
              row.read<int>('read_at'),
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> remove({
    required String userId,
    required String blogId,
  }) => database.customStatement(
    'DELETE FROM reading_history WHERE backend = ? AND user_id = ? AND blog_id = ?',
    [_backend, userId, blogId],
  );

  @override
  Future<void> clear({required String userId}) => database.customStatement(
    'DELETE FROM reading_history WHERE backend = ? AND user_id = ?',
    [_backend, userId],
  );
  @override
  Future<bool> hasUnattributedHistory() async =>
      (await database
          .customSelect(
            "SELECT 1 AS present FROM reading_history WHERE backend = '' LIMIT 1",
          )
          .getSingleOrNull()) !=
      null;

  @override
  Future<void> clearUnattributedHistory() => database.customStatement(
    "DELETE FROM reading_history WHERE backend = ''",
  );
}
