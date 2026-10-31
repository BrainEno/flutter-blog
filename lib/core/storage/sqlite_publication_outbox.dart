import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/domain/entities/queued_publication.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Durable publication intents, separate from ordinary editor drafts.
///
/// Every mutation is scoped to the owner. A cover is copied into the same
/// transaction as the intent rather than referencing a temporary picker file.
class SqlitePublicationOutbox {
  SqlitePublicationOutbox(this.database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const int maxCoverBytes = 8 * 1024 * 1024;
  static const Set<String> _coverTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final AppDatabase database;
  final DateTime Function() _now;

  static const _fields =
      'id, owner_id, title, content, tags, length(cover_bytes) AS cover_length, '
      'cover_mime, remote_cover_url, possible_orphan, status, phase, request_json, '
      'attempt_count, next_attempt_at, last_error_code, published_slug, '
      'created_at, updated_at';

  Future<QueuedPublication> enqueue({
    required String ownerId,
    required String title,
    required String content,
    required List<String> tags,
    Uint8List? coverBytes,
    String? coverMime,
  }) async {
    if (ownerId.trim().isEmpty ||
        title.trim().isEmpty ||
        content.trim().isEmpty) {
      throw ArgumentError('An owner, title and body are required.');
    }
    final mime = coverBytes == null
        ? null
        : (coverMime ?? 'image/jpeg').toLowerCase();
    if (coverBytes != null &&
        (coverBytes.isEmpty ||
            coverBytes.length > maxCoverBytes ||
            !_coverTypes.contains(mime))) {
      throw ArgumentError(
        'The cover must be a JPEG, PNG or WebP of at most 8 MiB.',
      );
    }
    final id = const Uuid().v4();
    final now = _now().toUtc().microsecondsSinceEpoch;
    await database.customInsert(
      'INSERT INTO publication_outbox '
      '(id, owner_id, title, content, tags, cover_bytes, cover_mime, status, phase, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(id),
        Variable<String>(ownerId),
        Variable<String>(title.trim()),
        Variable<String>(content.trim()),
        Variable<String>(jsonEncode(tags)),
        Variable<Uint8List>(
          coverBytes == null ? null : Uint8List.fromList(coverBytes),
        ),
        Variable<String>(mime),
        Variable<String>(PublicationStatus.queued.name),
        Variable<String>(PublicationPhase.ready.name),
        Variable<int>(now),
        Variable<int>(now),
      ],
    );
    return (await get(ownerId, id))!;
  }

  Future<List<QueuedPublication>> list(String ownerId) async {
    if (ownerId.isEmpty) return const [];
    final rows = await database
        .customSelect(
          'SELECT $_fields FROM publication_outbox WHERE owner_id = ? '
          'ORDER BY created_at DESC, id ASC',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    return rows.map(_fromRow).toList();
  }

  Future<bool> hasQueued(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT 1 AS present FROM publication_outbox WHERE owner_id = ? AND status = ? LIMIT 1',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(PublicationStatus.queued.name),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<QueuedPublication?> get(String ownerId, String id) async {
    final row = await database
        .customSelect(
          'SELECT $_fields FROM publication_outbox WHERE owner_id = ? AND id = ?',
          variables: [Variable<String>(ownerId), Variable<String>(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<Uint8List?> readCover(String ownerId, String id) async {
    final row = await database
        .customSelect(
          'SELECT cover_bytes FROM publication_outbox WHERE owner_id = ? AND id = ?',
          variables: [Variable<String>(ownerId), Variable<String>(id)],
        )
        .getSingleOrNull();
    return row?.readNullable<Uint8List>('cover_bytes');
  }

  /// Called once at process startup, before starting the worker. An interrupted
  /// media upload is ambiguous and must not be sent again automatically.
  Future<void> recoverInterrupted() => database.transaction(() async {
    final now = _now().toUtc().microsecondsSinceEpoch;
    await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, phase = ?, last_error_code = ?, '
      'possible_orphan = 1, next_attempt_at = NULL, updated_at = ? WHERE status = ? AND phase = ?',
      variables: [
        Variable<String>(PublicationStatus.failed.name),
        Variable<String>(PublicationPhase.mediaUncertain.name),
        Variable<String>('media.outcomeUnknown'),
        Variable<int>(now),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.mediaSending.name),
      ],
    );
    // The deployed server's idempotency capability cannot be negotiated.
    // An interrupted article POST is therefore reconciled, never resent
    // automatically just because the process restarted.
    await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, last_error_code = ?, '
      'next_attempt_at = NULL, updated_at = ? WHERE status = ? AND phase = ?',
      variables: [
        Variable<String>(PublicationStatus.failed.name),
        Variable<String>('article.outcomeUnknown'),
        Variable<int>(now),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.articleSending.name),
      ],
    );
    await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, next_attempt_at = NULL, updated_at = ? '
      'WHERE status = ?',
      variables: [
        Variable<String>(PublicationStatus.queued.name),
        Variable<int>(now),
        Variable<String>(PublicationStatus.uploading.name),
      ],
    );
  });

  /// Atomically claims one due item for this owner. A second worker cannot
  /// claim the same queued row while it is marked uploading.
  Future<QueuedPublication?> claimNext(
    String ownerId,
  ) => database.transaction(() async {
    final now = _now().toUtc().microsecondsSinceEpoch;
    final row = await database
        .customSelect(
          'SELECT $_fields FROM publication_outbox WHERE owner_id = ? AND status = ? '
          'AND (next_attempt_at IS NULL OR next_attempt_at <= ?) '
          'ORDER BY created_at ASC, id ASC LIMIT 1',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(PublicationStatus.queued.name),
            Variable<int>(now),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final id = row.read<String>('id');
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, attempt_count = attempt_count + 1, '
      'next_attempt_at = NULL, updated_at = ? WHERE owner_id = ? AND id = ? AND status = ?',
      variables: [
        Variable<String>(PublicationStatus.uploading.name),
        Variable<int>(now),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.queued.name),
      ],
    );
    if (count != 1) return null;
    return get(ownerId, id);
  });

  Future<bool> beginMedia(String ownerId, String id) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET phase = ?, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status = ? AND phase = ?',
      variables: [
        Variable<String>(PublicationPhase.mediaSending.name),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.ready.name),
      ],
    );
    return count == 1;
  }

  Future<bool> saveUploadedMedia(String ownerId, String id, String url) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET remote_cover_url = ?, phase = ?, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status = ? AND phase = ?',
      variables: [
        Variable<String>(url),
        Variable<String>(PublicationPhase.mediaReady.name),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.mediaSending.name),
      ],
    );
    return count == 1;
  }

  /// Stores the exact request before sending it. A subsequent attempt must
  /// reuse it verbatim, including the slug and content-block identifiers.
  Future<bool> beginArticle(
    String ownerId,
    String id,
    String requestJson,
  ) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET request_json = COALESCE(request_json, ?), '
      'phase = ?, updated_at = ? WHERE owner_id = ? AND id = ? AND status = ? '
      'AND phase IN (?, ?, ?) AND (request_json IS NULL OR request_json = ?)',
      variables: [
        Variable<String>(requestJson),
        Variable<String>(PublicationPhase.articleSending.name),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.ready.name),
        Variable<String>(PublicationPhase.mediaReady.name),
        Variable<String>(PublicationPhase.articleSending.name),
        Variable<String>(requestJson),
      ],
    );
    return count == 1;
  }

  Future<bool> markPublished(String ownerId, String id, String slug) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, phase = ?, published_slug = ?, '
      'cover_bytes = NULL, cover_mime = NULL, request_json = NULL, '
      'next_attempt_at = NULL, last_error_code = NULL, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status = ? AND phase = ?',
      variables: [
        Variable<String>(PublicationStatus.published.name),
        Variable<String>(PublicationPhase.complete.name),
        Variable<String>(slug),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.articleSending.name),
      ],
    );
    return count == 1;
  }

  /// A documented validation/auth rejection means the article was not
  /// created. Unfreeze its body so the user can fix it or sign in again.
  Future<bool> rejectArticle(String ownerId, String id, String code) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, '
      'phase = CASE WHEN remote_cover_url IS NULL THEN ? ELSE ? END, '
      'request_json = NULL, last_error_code = ?, next_attempt_at = NULL, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status = ? AND phase = ?',
      variables: [
        Variable<String>(PublicationStatus.failed.name),
        Variable<String>(PublicationPhase.ready.name),
        Variable<String>(PublicationPhase.mediaReady.name),
        Variable<String>(code),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
        Variable<String>(PublicationPhase.articleSending.name),
      ],
    );
    return count == 1;
  }

  /// Reconciliation requires the caller to verify owner, slug and frozen
  /// content against a server response. A 404 is not such a confirmation.
  Future<bool> markReconciled(String ownerId, String id, String slug) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, phase = ?, published_slug = ?, '
      'cover_bytes = NULL, cover_mime = NULL, request_json = NULL, '
      'next_attempt_at = NULL, last_error_code = NULL, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status IN (?, ?) AND phase = ?',
      variables: [
        Variable<String>(PublicationStatus.published.name),
        Variable<String>(PublicationPhase.complete.name),
        Variable<String>(slug),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.failed.name),
        Variable<String>(PublicationStatus.queued.name),
        Variable<String>(PublicationPhase.articleSending.name),
      ],
    );
    return count == 1;
  }

  Future<bool> failAttempt(
    String ownerId,
    String id, {
    required String code,
    DateTime? retryAt,
    PublicationPhase? phase,
  }) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, phase = COALESCE(?, phase), '
      'possible_orphan = CASE WHEN ? = ? THEN 1 ELSE possible_orphan END, '
      'last_error_code = ?, next_attempt_at = ?, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status = ?',
      variables: [
        Variable<String>(
          retryAt == null
              ? PublicationStatus.failed.name
              : PublicationStatus.queued.name,
        ),
        Variable<String>(phase?.name),
        Variable<String>(phase?.name),
        Variable<String>(PublicationPhase.mediaUncertain.name),
        Variable<String>(code),
        Variable<int>(retryAt?.toUtc().microsecondsSinceEpoch),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
      ],
    );
    return count == 1;
  }

  /// Defers a claimed item when the matching session is no longer usable.
  Future<bool> deferForSession(String ownerId, String id) async {
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, attempt_count = MAX(attempt_count - 1, 0), '
      'last_error_code = ?, updated_at = ? WHERE owner_id = ? AND id = ? AND status = ?',
      variables: [
        Variable<String>(PublicationStatus.queued.name),
        Variable<String>('auth.ownerUnavailable'),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.uploading.name),
      ],
    );
    return count == 1;
  }

  Future<bool> retry(
    String ownerId,
    String id, {
    bool acceptMediaReupload = false,
  }) async {
    final row = await get(ownerId, id);
    if (row == null || row.status != PublicationStatus.failed) return false;
    // A POST with unknown outcome must be checked, not sent again against an
    // unverified server. In particular, a 404 does not prove non-creation.
    if (row.articleOutcomeUncertain) return false;
    if (row.phase == PublicationPhase.mediaUncertain && !acceptMediaReupload) {
      return false;
    }
    final phase = row.phase == PublicationPhase.mediaUncertain
        ? PublicationPhase.ready
        : row.phase;
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET status = ?, phase = ?, attempt_count = 0, '
      'next_attempt_at = NULL, last_error_code = NULL, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status = ? AND phase = ?',
      variables: [
        Variable<String>(PublicationStatus.queued.name),
        Variable<String>(phase.name),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.failed.name),
        Variable<String>(row.phase.name),
      ],
    );
    return count == 1;
  }

  Future<bool> edit(
    String ownerId,
    String id, {
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    if (title.trim().isEmpty || content.trim().isEmpty) return false;
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET title = ?, content = ?, tags = ?, updated_at = ? '
      'WHERE owner_id = ? AND id = ? AND status IN (?, ?) AND phase IN (?, ?, ?)',
      variables: [
        Variable<String>(title.trim()),
        Variable<String>(content.trim()),
        Variable<String>(jsonEncode(tags)),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(PublicationStatus.queued.name),
        Variable<String>(PublicationStatus.failed.name),
        Variable<String>(PublicationPhase.ready.name),
        Variable<String>(PublicationPhase.mediaReady.name),
        Variable<String>(PublicationPhase.mediaUncertain.name),
      ],
    );
    return count == 1;
  }

  /// Remove a cover before the article POST. A possibly created remote
  /// asset cannot be removed by the current API, so confirmation is required.
  Future<bool> removeCover(
    String ownerId,
    String id, {
    bool acceptPossibleOrphan = false,
  }) async {
    final row = await get(ownerId, id);
    if (row == null || !row.canEdit || !row.hasCover) return false;
    if (row.mayHaveRemoteOrphan && !acceptPossibleOrphan) return false;
    final count = await database.customUpdate(
      'UPDATE publication_outbox SET cover_bytes = NULL, cover_mime = NULL, '
      'possible_orphan = CASE WHEN remote_cover_url IS NOT NULL THEN 1 ELSE possible_orphan END, '
      'remote_cover_url = NULL, phase = ?, status = ?, last_error_code = NULL, '
      'next_attempt_at = NULL, updated_at = ? WHERE owner_id = ? AND id = ? '
      'AND status = ? AND phase = ? AND possible_orphan = ? AND remote_cover_url IS ?',
      variables: [
        Variable<String>(PublicationPhase.ready.name),
        Variable<String>(PublicationStatus.failed.name),
        Variable<int>(_now().toUtc().microsecondsSinceEpoch),
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(row.status.name),
        Variable<String>(row.phase.name),
        Variable<int>(row.possibleOrphan ? 1 : 0),
        Variable<String>(row.remoteCoverUrl),
      ],
    );
    return count == 1;
  }

  /// Removing an item after a media upload can leave an unreferenced server
  /// asset. Callers must warn and receive an explicit confirmation first.
  /// An article whose outcome is unknown cannot be removed as if unpublished.
  Future<bool> remove(
    String ownerId,
    String id, {
    bool acceptPossibleOrphan = false,
  }) async {
    final row = await get(ownerId, id);
    if (row == null ||
        row.status == PublicationStatus.uploading ||
        row.articleOutcomeUncertain) {
      return false;
    }
    if (row.mayHaveRemoteOrphan && !acceptPossibleOrphan) return false;
    final count = await database.customUpdate(
      'DELETE FROM publication_outbox WHERE owner_id = ? AND id = ? AND status = ? AND phase = ? '
      'AND possible_orphan = ? AND remote_cover_url IS ?',
      variables: [
        Variable<String>(ownerId),
        Variable<String>(id),
        Variable<String>(row.status.name),
        Variable<String>(row.phase.name),
        Variable<int>(row.possibleOrphan ? 1 : 0),
        Variable<String>(row.remoteCoverUrl),
      ],
    );
    return count == 1;
  }

  QueuedPublication _fromRow(QueryRow row) {
    DateTime? time(String name) {
      final value = row.readNullable<int>(name);
      return value == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
    }

    return QueuedPublication(
      id: row.read<String>('id'),
      ownerId: row.read<String>('owner_id'),
      title: row.read<String>('title'),
      content: row.read<String>('content'),
      tags: (jsonDecode(row.read<String>('tags')) as List).cast<String>(),
      hasCover: row.readNullable<int>('cover_length') != null,
      coverMime: row.readNullable<String>('cover_mime'),
      remoteCoverUrl: row.readNullable<String>('remote_cover_url'),
      possibleOrphan: row.read<int>('possible_orphan') != 0,
      status: PublicationStatus.values.byName(row.read<String>('status')),
      phase: PublicationPhase.values.byName(row.read<String>('phase')),
      requestJson: row.readNullable<String>('request_json'),
      attemptCount: row.read<int>('attempt_count'),
      nextAttemptAt: time('next_attempt_at'),
      lastErrorCode: row.readNullable<String>('last_error_code'),
      publishedSlug: row.readNullable<String>('published_slug'),
      createdAt: time('created_at')!,
      updatedAt: time('updated_at')!,
    );
  }
}
