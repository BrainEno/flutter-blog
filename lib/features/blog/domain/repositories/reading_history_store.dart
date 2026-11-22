import 'package:belog/core/config/app_limits.dart';
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

  /// How far into the article the reader last was, from 0 to 1; null when
  /// it was never measured (see [ReadingHistoryStore.saveProgress]).
  final double? progress;

  const ReadingHistoryEntry({
    required this.blogId,
    required this.title,
    required this.posterName,
    required this.imageUrl,
    required this.readAt,
    this.progress,
  });
}

/// Where a saved reading position starts to mean something.
abstract final class ReadingProgress {
  /// Below this the reader had barely begun: no offer to go back, and no
  /// percentage in the history.
  static const started = 0.05;

  /// From here the text is behind the reader - the end mark is in sight -
  /// and the article counts as read.
  static const finished = 0.95;
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
    int limit = AppLimits.readingHistoryPageSize,
  });

  /// Remembers where [userId] left [blogId], as a share of the article's
  /// text from 0 to 1, so the reader can pick up there next time. Only an
  /// article already in the history is updated: the position belongs to its
  /// entry and goes when the entry does.
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  });

  /// Where [userId] last left [blogId], or null when unknown.
  Future<double?> progressOf({required String userId, required String blogId});

  /// Deletes one entry.
  Future<void> remove({required String userId, required String blogId});

  /// Deletes every entry of [userId].
  Future<void> clear({required String userId});
}

/// Optional device-wide maintenance for pre-backend history. These rows cannot
/// be attributed to any account or server and must never be returned as normal
/// history. Deletion is explicit and affects the entire unattributed namespace.
abstract interface class UnattributedHistoryMaintenance {
  Future<bool> hasUnattributedHistory();
  Future<void> clearUnattributedHistory();
}
