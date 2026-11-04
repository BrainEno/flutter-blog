import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:drift/drift.dart';

class SqliteReadingHistoryStore implements ReadingHistoryStore {
  final AppDatabase database;
  SqliteReadingHistoryStore(this.database);

  @override
  Future<void> record({required String userId, required Blog blog}) {
    return database.customStatement(
      'INSERT INTO reading_history(user_id, blog_id, title, poster_name, image_url, read_at) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(user_id, blog_id) DO UPDATE SET title = excluded.title, '
      'poster_name = excluded.poster_name, image_url = excluded.image_url, '
      'read_at = excluded.read_at',
      [
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
    int limit = 200,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT blog_id, title, poster_name, image_url, read_at '
          'FROM reading_history WHERE user_id = ? '
          'ORDER BY read_at DESC LIMIT ?',
          variables: [Variable<String>(userId), Variable<int>(limit)],
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
  Future<void> remove({required String userId, required String blogId}) =>
      database.customStatement(
        'DELETE FROM reading_history WHERE user_id = ? AND blog_id = ?',
        [userId, blogId],
      );

  @override
  Future<void> clear({required String userId}) => database.customStatement(
    'DELETE FROM reading_history WHERE user_id = ?',
    [userId],
  );
}
