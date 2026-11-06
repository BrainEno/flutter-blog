import 'dart:convert';
import 'dart:io';

import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// SQLite-backed publish queue (issue #23).
///
/// Rows are namespaced by the API origin, exactly like the draft store: an
/// install that is repointed at another backend must not send the previous
/// backend's pending articles there.
class SqlitePublishQueueStore implements PublishQueueStore {
  SqlitePublishQueueStore(
    this.database, {
    required Uri apiBaseUrl,
    required Directory directory,
    Uuid? uuid,
  }) : _backend = backendKeyOf(apiBaseUrl),
       _directory = directory,
       _uuid = uuid ?? const Uuid();

  final AppDatabase database;

  /// Where cover files live (inside the app's documents directory).
  final Directory _directory;
  final Uuid _uuid;

  final String _backend;
  Future<void> _writeTail = Future<void>.value();

  Future<T> _serializeWrite<T>(Future<T> Function() body) {
    final result = _writeTail.then((_) => body());
    _writeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<PublishQueueEntry> enqueue({
    required String userId,
    required String title,
    required String content,
    required List<String> tags,
    required String idempotencyKey,
    ImageUpload? cover,
    PublishQueueKind kind = PublishQueueKind.create,
    String? targetId,
  }) {
    if (userId.isEmpty) {
      throw ArgumentError('A queued publish needs the account that asked.');
    }
    if (idempotencyKey.isEmpty) {
      throw ArgumentError('A queued publish needs an idempotency key.');
    }
    if (kind == PublishQueueKind.edit && (targetId ?? '').isEmpty) {
      throw ArgumentError('A queued edit needs the article it updates.');
    }
    final id = _uuid.v4();
    // Copy the bytes before the write waits for its turn: the caller may drop
    // its reference (a picker cache file) as soon as this future returns.
    final coverBytes = cover?.bytes;
    final coverMime = cover?.mimeType;
    final now = DateTime.now();
    return _serializeWrite(() async {
      String? coverFileName;
      if (coverBytes != null && coverBytes.isNotEmpty) {
        final file = File('${_directory.path}/$id.bin');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(coverBytes, flush: true);
        coverFileName = '$id.bin';
      }
      await database.customInsert(
        'INSERT INTO publish_queue(id, backend, user_id, idempotency_key, '
        'title, content, tags, cover_file, cover_mime, cover_url, kind, '
        'target_id, state, attempts, next_attempt_at, last_error_code, '
        'created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(_backend),
          Variable<String>(userId),
          Variable<String>(idempotencyKey),
          Variable<String>(title),
          Variable<String>(content),
          Variable<String>(jsonEncode(tags)),
          Variable<String>(coverFileName),
          Variable<String>(coverMime),
          Variable<String>(null),
          Variable<String>(kind.name),
          Variable<String>(kind == PublishQueueKind.edit ? targetId : null),
          Variable<String>(PublishQueueStatus.queued.name),
          Variable<int>(now.microsecondsSinceEpoch),
          Variable<int>(now.microsecondsSinceEpoch),
        ],
      );
      return PublishQueueEntry(
        id: id,
        userId: userId,
        title: title,
        content: content,
        tags: List<String>.unmodifiable(tags),
        idempotencyKey: idempotencyKey,
        kind: kind,
        targetId: kind == PublishQueueKind.edit ? targetId : null,
        status: PublishQueueStatus.queued,
        attempts: 0,
        createdAt: now,
        updatedAt: now,
        coverFileName: coverFileName,
        coverMimeType: coverFileName == null ? null : coverMime,
      );
    });
  }

  @override
  Future<List<PublishQueueEntry>> entries({required String userId}) async {
    await _writeTail;
    final rows = await database
        .customSelect(
          'SELECT * FROM publish_queue WHERE backend = ? AND user_id = ? '
          'ORDER BY created_at ASC, id ASC',
          variables: [Variable<String>(_backend), Variable<String>(userId)],
        )
        .get();
    return rows.map(_entryOf).toList(growable: false);
  }

  @override
  Future<PublishQueueEntry?> claimNext({
    required String userId,
    required DateTime now,
  }) {
    return _serializeWrite(() async {
      PublishQueueEntry? claimed;
      await database.transaction(() async {
        final row = await database
            .customSelect(
              'SELECT * FROM publish_queue WHERE backend = ? AND user_id = ? '
              'AND state = ? '
              'AND (next_attempt_at IS NULL OR next_attempt_at <= ?) '
              'ORDER BY created_at ASC, id ASC LIMIT 1',
              variables: [
                Variable<String>(_backend),
                Variable<String>(userId),
                Variable<String>(PublishQueueStatus.queued.name),
                Variable<int>(now.microsecondsSinceEpoch),
              ],
            )
            .getSingleOrNull();
        if (row == null) return;
        final updated = await database.customUpdate(
          'UPDATE publish_queue SET state = ?, updated_at = ? '
          'WHERE id = ? AND state = ?',
          variables: [
            Variable<String>(PublishQueueStatus.uploading.name),
            Variable<int>(now.microsecondsSinceEpoch),
            Variable<String>(row.read<String>('id')),
            Variable<String>(PublishQueueStatus.queued.name),
          ],
        );
        if (updated != 1) return;
        claimed = _entryOf(
          row,
        ).copyWith(status: PublishQueueStatus.uploading, updatedAt: now);
      });
      return claimed;
    });
  }

  @override
  Future<ImageUpload?> readCover(PublishQueueEntry entry) async {
    final fileName = entry.coverFileName;
    if (fileName == null || fileName.isEmpty) return null;
    final file = File('${_directory.path}/$fileName');
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return ImageUpload(
      bytes: bytes,
      mimeType: entry.coverMimeType ?? ImageUpload.defaultMimeType,
    );
  }

  @override
  Future<void> complete(String id) => _deleteWithCover(id);

  @override
  Future<void> remove(String id) => _deleteWithCover(id);

  @override
  Future<void> retry(String id) {
    return _serializeWrite(() async {
      await database.customStatement(
        'UPDATE publish_queue SET state = ?, attempts = 0, '
        'next_attempt_at = NULL, last_error_code = NULL, updated_at = ? '
        'WHERE id = ? AND backend = ?',
        [
          PublishQueueStatus.queued.name,
          DateTime.now().microsecondsSinceEpoch,
          id,
          _backend,
        ],
      );
    });
  }

  Future<void> _deleteWithCover(String id) {
    return _serializeWrite(() async {
      final row = await database
          .customSelect(
            'SELECT cover_file FROM publish_queue WHERE id = ? AND backend = ?',
            variables: [Variable<String>(id), Variable<String>(_backend)],
          )
          .getSingleOrNull();
      await database.customStatement(
        'DELETE FROM publish_queue WHERE id = ? AND backend = ?',
        [id, _backend],
      );
      final fileName = row?.readNullable<String>('cover_file');
      if (fileName != null && fileName.isNotEmpty) {
        try {
          final file = File('${_directory.path}/$fileName');
          if (await file.exists()) await file.delete();
        } catch (error) {
          // A leftover cover is harmless; a queue row that never clears is not.
          AppLogger.debug('could not delete a queued cover | $error');
        }
      }
    });
  }

  @override
  Future<void> release(String id) {
    return _serializeWrite(() async {
      await database.customStatement(
        'UPDATE publish_queue SET state = ?, updated_at = ? '
        'WHERE id = ? AND backend = ? AND state = ?',
        [
          PublishQueueStatus.queued.name,
          DateTime.now().microsecondsSinceEpoch,
          id,
          _backend,
          PublishQueueStatus.uploading.name,
        ],
      );
    });
  }

  @override
  Future<void> recordCoverUrl(String id, {required String url}) {
    return _serializeWrite(() async {
      await database.customStatement(
        'UPDATE publish_queue SET cover_url = ?, updated_at = ? '
        'WHERE id = ? AND backend = ?',
        [url, DateTime.now().microsecondsSinceEpoch, id, _backend],
      );
    });
  }

  @override
  Future<void> recordFailure(
    String id, {
    required String errorCode,
    required bool retryable,
    DateTime? nextAttemptAt,
    bool countAttempt = true,
  }) {
    return _serializeWrite(() async {
      final now = DateTime.now();
      await database.customStatement(
        'UPDATE publish_queue SET state = ?, attempts = attempts + ?, '
        'next_attempt_at = ?, last_error_code = ?, updated_at = ? '
        'WHERE id = ? AND backend = ?',
        [
          retryable
              ? PublishQueueStatus.queued.name
              : PublishQueueStatus.failed.name,
          countAttempt ? 1 : 0,
          retryable ? nextAttemptAt?.microsecondsSinceEpoch : null,
          errorCode,
          now.microsecondsSinceEpoch,
          id,
          _backend,
        ],
      );
    });
  }

  @override
  Future<void> recoverInterrupted() {
    return _serializeWrite(() async {
      await database.customStatement(
        'UPDATE publish_queue SET state = ? WHERE backend = ? AND state = ?',
        [
          PublishQueueStatus.queued.name,
          _backend,
          PublishQueueStatus.uploading.name,
        ],
      );
    });
  }

  PublishQueueEntry _entryOf(QueryRow row) {
    return PublishQueueEntry(
      id: row.read<String>('id'),
      userId: row.read<String>('user_id'),
      title: row.read<String>('title'),
      content: row.read<String>('content'),
      tags: (jsonDecode(row.read<String>('tags')) as List).cast<String>(),
      idempotencyKey: row.read<String>('idempotency_key'),
      status: PublishQueueStatus.values.firstWhere(
        (value) => value.name == row.read<String>('state'),
        orElse: () => PublishQueueStatus.failed,
      ),
      attempts: row.read<int>('attempts'),
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row.read<int>('created_at'),
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row.read<int>('updated_at'),
      ),
      coverFileName: row.readNullable<String>('cover_file'),
      coverMimeType: row.readNullable<String>('cover_mime'),
      coverUrl: row.readNullable<String>('cover_url'),
      kind: PublishQueueKind.values.firstWhere(
        (value) => value.name == row.read<String>('kind'),
        orElse: () => PublishQueueKind.create,
      ),
      targetId: row.readNullable<String>('target_id'),
      nextAttemptAt: _timeOf(row.readNullable<int>('next_attempt_at')),
      lastErrorCode: row.readNullable<String>('last_error_code'),
    );
  }

  static DateTime? _timeOf(int? microseconds) {
    if (microseconds == null) return null;
    return DateTime.fromMicrosecondsSinceEpoch(microseconds);
  }
}
