import 'package:belog/features/blog/domain/entities/blog.dart';

/// One entry of the device-local reading history (issue #22).
///
/// Pure Dart value object; display fields are snapshots taken when the
/// article was read, so the list stays presentable even after the article
/// drops out of the bounded blog cache.
class ReadingHistoryEntry {
  final String blogId;
  final String title;
  final String posterName;
  final String imageUrl;
  final DateTime readAt;

  const ReadingHistoryEntry({
    required this.blogId,
    required this.title,
    required this.posterName,
    required this.imageUrl,
    required this.readAt,
  });
}

/// Device-local reading history, scoped per signed-in account.
///
/// The history is never synced anywhere; signing out clears it (see
/// `AuthRepositoryImpl.logout`), and the user can delete single entries or
/// the whole list from the history page.
abstract class ReadingHistoryStore {
  /// Records (or re-records) [blog] as just read by [userId]: the composite
  /// primary key deduplicates re-reads and bumps [ReadingHistoryEntry.readAt].
  Future<void> record({required String userId, required Blog blog});

  /// The user's most recent reads, newest first.
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  });

  /// Deletes one entry.
  Future<void> remove({required String userId, required String blogId});

  /// Deletes every entry of [userId].
  Future<void> clear({required String userId});
}
