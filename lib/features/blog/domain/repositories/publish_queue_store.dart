import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';

/// Durable store for publishes that still owe the server a request
/// (issue #23).
///
/// Implementations must scope rows by account and by backend: an entry queued
/// against one API origin, or by one account, must never be sent by another.
/// The port deliberately knows nothing about HTTP, sessions or widgets.
abstract interface class PublishQueueStore {
  /// Stores a new intent and returns the pending entry.
  ///
  /// [cover], when present, is copied into the app's own storage before this
  /// future completes: the caller's bytes usually come from a picker cache
  /// that may be cleaned up while the entry waits.
  ///
  /// [kind] and [targetId] say whether this entry creates an article or
  /// updates one. An [PublishQueueKind.edit] entry must name its article:
  /// without a target there is nothing to update, so implementations reject it
  /// the same way they reject a missing account.
  ///
  /// [locale] is the language edition an edit writes. Without it a replay
  /// falls back to whatever content language is in effect then, which for a
  /// non-default edition means rewriting the wrong translation.
  Future<PublishQueueEntry> enqueue({
    required String userId,
    required String title,
    required String content,
    required List<String> tags,
    required String idempotencyKey,
    ImageUpload? cover,

    /// A media-library cover selected before the request was queued.
    ///
    /// When present, the retry reuses this immutable asset rather than
    /// uploading new bytes. [cover] may also be present if an earlier attempt
    /// already uploaded a locally selected file.
    String? coverUrl,
    PublishQueueKind kind = PublishQueueKind.create,
    String? targetId,
    String? locale,

    /// The author's category choice at queue time; null leaves the article's
    /// categories alone when the entry is eventually sent.
    List<String>? categoryIds,
  });

  /// Every entry this account queued, oldest first, including failed ones.
  Future<List<PublishQueueEntry>> entries({required String userId});

  /// The oldest entry that is due, atomically moved to
  /// [PublishQueueStatus.uploading].
  ///
  /// Returns null when nothing is due: no entries, all of them waiting for a
  /// backoff window, or all of them belonging to another account. Claiming
  /// before sending is what keeps two drains from publishing the same entry.
  Future<PublishQueueEntry?> claimNext({
    required String userId,
    required DateTime now,
  });

  /// The stored cover bytes, or null when the entry has no cover file.
  Future<ImageUpload?> readCover(PublishQueueEntry entry);

  /// Remembers the URL an attempt just uploaded the cover to.
  ///
  /// Callers must await this *before* creating the article: a crash between
  /// the two must not make the next attempt upload a second copy of the same
  /// bytes. Immutable media means a recorded URL stays valid for the retry.
  Future<void> recordCoverUrl(String id, {required String url});

  /// The server accepted the entry: drop it and its cover file.
  Future<void> complete(String id);

  /// Put a claimed entry back in the queue without counting an attempt
  /// (used when the session changed mid-drain, or the process was interrupted).
  Future<void> release(String id);

  /// Records a failed send.
  ///
  /// A retryable failure keeps the entry [PublishQueueStatus.queued] with
  /// [nextAttemptAt] and one more attempt; a permanent one moves it to
  /// [PublishQueueStatus.failed] so the UI can ask a human.
  ///
  /// [countAttempt] is false for failures the entry did not cause (a missing
  /// session): those wait for the user to sign in without spending the retry
  /// budget.
  Future<void> recordFailure(
    String id, {
    required String errorCode,
    required bool retryable,
    DateTime? nextAttemptAt,
    bool countAttempt = true,
  });

  /// Deletes an entry and its cover file (user cancelled it).
  Future<void> remove(String id);

  /// Puts an entry back in line now, with a fresh retry budget (the user asked
  /// for it). The idempotency key is unchanged, so a manual retry is as safe as
  /// an automatic one.
  Future<void> retry(String id);

  /// Startup repair: an entry left [PublishQueueStatus.uploading] by a killed
  /// process is due again. Safe because the retry reuses its idempotency key,
  /// so a send that did reach the server is replayed instead of duplicated.
  Future<void> recoverInterrupted();
}
