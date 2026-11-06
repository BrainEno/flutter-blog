import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:fpdart/fpdart.dart';

/// Sends queued publishes, one at a time, for the account that is signed in
/// right now (issue #23).
///
/// The rules it enforces, in this order:
///
/// - **The right account.** An entry names the account that queued it; if the
///   active session is somebody else, the entry stays queued. A user who signs
///   out and back in as the same account resumes normally, because the fence is
///   rebuilt from the *current* session before every send: the queue is a
///   standing intent of that account, not a stale token from the old one.
/// - **One send at a time.** The store claims an entry before it is sent, so two
///   drains cannot publish the same entry, and a crash mid-send leaves a row
///   that the next launch repairs.
/// - **Never silently twice.** A new article's every attempt carries the
///   entry's `Idempotency-Key`, so a retry after a lost response replays the
///   article the server already created instead of publishing a second copy.
///   An edit needs no key of its own: it addresses one article id, so replaying
///   it rewrites that article instead of creating another.
/// - **One cover upload.** Media assets are immutable, so the URL an attempt
///   uploaded the cover to is written back to the entry before the article is
///   created: a retry (or a crash between the two steps) reuses that URL and
///   never leaves a second unreferenced asset behind.
/// - **Bounded retries.** Network, timeout and storage failures back off
///   (1m, 5m, 15m, 60m, 3h) up to [_kMaxAttempts]; content rejections stop
///   immediately and wait for a human. A missing session pauses the queue
///   without spending the retry budget, because only signing in again can fix
///   it.
class PublishQueueRunner implements PublishQueueDrainer {
  PublishQueueRunner({
    required this.store,
    required this.repository,
    required this.identity,
    required this.connectionChecker,
  });

  final PublishQueueStore store;
  final BlogRepository repository;
  final NowaveSessionIdentity identity;
  final ConnectionChecker connectionChecker;

  /// How many attempts an entry gets before it stops retrying on its own.
  static const int _kMaxAttempts = 5;

  /// One drain at a time; a second call while a send is in flight is a no-op.
  bool _running = false;

  /// Sends what is due for the active account and stops at the first failure.
  ///
  /// Returns the number of entries the server accepted.
  @override
  Future<int> drain() async {
    if (_running) return 0;
    final userId = identity.activeUserId;
    if (userId == null || userId.isEmpty) return 0;
    _running = true;
    var sent = 0;
    try {
      if (!await connectionChecker.isConnected) return 0;
      while (true) {
        final entry = await store.claimNext(
          userId: userId,
          now: DateTime.now(),
        );
        if (entry == null) break;
        if (identity.activeUserId != userId) {
          // The session changed between the claim and the send. Put the entry
          // back untouched: it is not this drain's to send.
          await store.release(entry.id);
          break;
        }
        final accepted = await _send(entry);
        if (!accepted) break;
        sent++;
      }
    } catch (error) {
      AppLogger.error('the publish queue stopped unexpectedly', error: error);
    } finally {
      _running = false;
    }
    return sent;
  }

  Future<bool> _send(PublishQueueEntry entry) async {
    final fence = NowaveSessionFence(
      userId: entry.userId,
      generation: identity.sessionGeneration,
    );

    final targetId = entry.targetId;
    if (entry.kind == PublishQueueKind.edit && (targetId ?? '').isEmpty) {
      // Nothing to update, and no retry can invent the article. Stop and let a
      // human decide instead of spending the retry budget.
      await _fail(
        entry,
        const Failure(
          '这条队列缺少要更新的文章',
          kind: FailureKind.validation,
          code: 'publish_queue.missing_target',
        ),
      );
      return false;
    }

    // An earlier attempt may already have uploaded the cover. Reuse that asset
    // instead of sending the same bytes again (see [_uploadCover]).
    var coverUrl = entry.coverUrl;
    if (coverUrl == null) {
      final uploaded = await _uploadCover(entry, fence);
      if (uploaded == null) return false;
      if (uploaded.isNotEmpty) coverUrl = uploaded;
    }

    try {
      final Either<Failure, Blog> result;
      if (entry.kind == PublishQueueKind.edit) {
        result = await repository.editBlog(
          blogId: targetId!,
          title: entry.title,
          content: entry.content,
          tags: entry.tags,
          uploadedCoverUrl: coverUrl,
          sessionFence: fence,
        );
      } else {
        result = await repository.uploadBlog(
          uploadedCoverUrl: coverUrl,
          title: entry.title,
          content: entry.content,
          posterId: entry.userId,
          tags: entry.tags,
          idempotencyKey: entry.idempotencyKey,
          sessionFence: fence,
        );
      }
      final failure = result.fold<Failure?>((error) => error, (_) => null);
      if (failure == null) {
        await store.complete(entry.id);
        return true;
      }
      await _fail(entry, failure);
      return false;
    } catch (error) {
      // The repository maps its own exceptions; this is a last-resort guard so
      // one bad entry cannot wedge the whole queue in `uploading`.
      await _fail(
        entry,
        Failure('发布遇到未知错误', kind: FailureKind.unknown, cause: error),
      );
      return false;
    }
  }

  /// Uploads the entry's cover once and records the URL on the entry.
  ///
  /// Returns the URL to publish with, or an empty string when the entry has no
  /// cover bytes at all (a text-only article). Returns null when the send must
  /// stop here, because the cover is unreadable or the upload failed: the entry
  /// has already been marked accordingly.
  ///
  /// Recording the URL *before* the article request is what makes a crash
  /// between the two steps cheap: the next attempt reuses the asset instead of
  /// uploading a second copy of the same bytes.
  Future<String?> _uploadCover(
    PublishQueueEntry entry,
    NowaveSessionFence fence,
  ) async {
    ImageUpload? cover;
    try {
      cover = await store.readCover(entry);
    } catch (error) {
      AppLogger.debug('queued cover could not be read | $error');
      await _fail(
        entry,
        Failure(
          '封面文件无法读取',
          kind: FailureKind.storage,
          code: 'publish_queue.cover_unreadable',
        ),
      );
      return null;
    }
    if (cover == null) return '';

    final uploaded = await repository.uploadCover(
      image: cover,
      sessionFence: fence,
    );
    final failure = uploaded.fold<Failure?>((error) => error, (_) => null);
    if (failure != null) {
      await _fail(entry, failure);
      return null;
    }
    final url = uploaded.fold((_) => '', (value) => value);
    if (url.isEmpty) {
      AppLogger.debug('queued cover upload returned no URL | ${entry.id}');
      return '';
    }

    try {
      await store.recordCoverUrl(entry.id, url: url);
    } catch (error) {
      // Best effort: losing the record only costs one more upload on a later
      // attempt. Failing the whole send here would punish the article.
      AppLogger.debug('queued cover URL could not be stored | $error');
    }
    return url;
  }

  Future<void> _fail(PublishQueueEntry entry, Failure failure) async {
    final kind = failure.kind;
    final retryable = _isRetryable(kind, entry.attempts);
    DateTime? nextAttemptAt;
    if (retryable) {
      // A missing session waits briefly, so the backoff cannot hide a sign-in
      // prompt from the user.
      final wait = kind == FailureKind.auth ? 0 : entry.attempts;
      nextAttemptAt = DateTime.now().add(_backoffFor(wait));
    }
    await store.recordFailure(
      entry.id,
      errorCode: failure.code ?? kind.name,
      retryable: retryable,
      nextAttemptAt: nextAttemptAt,
      countAttempt: kind != FailureKind.auth,
    );
    AppLogger.debug('queued publish ${entry.id} failed: $kind ($retryable)');
  }

  /// Whether another attempt can plausibly succeed.
  ///
  /// [attempts] is how many times the entry already failed: content or
  /// permission rejections never retry, and server or unknown errors only
  /// retry a bounded number of times.
  static bool _isRetryable(FailureKind kind, int attempts) {
    if (kind == FailureKind.permission || kind == FailureKind.validation) {
      return false;
    }
    if (kind == FailureKind.server || kind == FailureKind.unknown) {
      return attempts + 1 < _kMaxAttempts;
    }
    // Network, timeout, storage and a missing session can all succeed later.
    return true;
  }

  static Duration _backoffFor(int attempts) => switch (attempts) {
    0 => const Duration(minutes: 1),
    1 => const Duration(minutes: 5),
    2 => const Duration(minutes: 15),
    3 => const Duration(minutes: 60),
    _ => const Duration(hours: 3),
  };
}
