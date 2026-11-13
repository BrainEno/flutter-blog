import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';
import 'package:drift/drift.dart';

/// SQLite body recovery for existing article editions. Atomic local revision
/// comparisons protect multiple store instances/editors; they are not a
/// server-side version check and do not make remote publication safe.
class SqliteStructuredBodyRecoveryStore
    implements StructuredTextSessionStore, StructuredRecoveryCatalog {
  SqliteStructuredBodyRecoveryStore(this.database, {required Uri apiBaseUrl})
    : _backend = backendKeyOf(apiBaseUrl);

  final AppDatabase database;
  final String _backend;

  /// Bounded keyset pagination, scoped before reading any identity values.
  /// Only short key columns are read; bodies and metadata are decoded on open.
  @override
  Future<StructuredRecoveryIndexPage> page({
    required String userId,
    int? afterRowId,
  }) async {
    if (userId.isEmpty ||
        userId != userId.trim() ||
        (afterRowId != null && afterRowId <= 0)) {
      throw ArgumentError('Invalid catalog identity or cursor');
    }
    const pageSize = 25;
    final rows = await database
        .customSelect(
          'SELECT id, substr(article_id, 1, 4097) AS article, '
          'substr(locale, 1, 17) AS edition FROM structured_body_drafts '
          'WHERE backend = ? AND user_id = ? AND id > ? ORDER BY id LIMIT ?',
          variables: [
            Variable<String>(_backend),
            Variable<String>(userId),
            Variable<int>(afterRowId ?? 0),
            Variable<int>(pageSize + 1),
          ],
        )
        .get();
    final entries = <StructuredRecoveryIndexEntry>[];
    for (final row in rows.take(pageSize)) {
      final id = row.read<int>('id');
      final article = row.read<String>('article');
      final locale = row.read<String>('edition');
      StructuredBodyKey? key;
      try {
        if (id > 0 && article.length <= 4096) {
          key = StructuredBodyKey(
            userId: userId,
            articleId: article,
            locale: locale,
          );
        }
      } on ArgumentError {
        // Keep damaged identity visible without trying to read or repair it.
      }
      entries.add(StructuredRecoveryIndexEntry(rowId: id, key: key));
    }
    return StructuredRecoveryIndexPage(
      entries: entries,
      nextCursor: rows.length > pageSize ? entries.last.rowId : null,
    );
  }

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) => _load(key);

  Future<StructuredBodyRecovery?> _load(
    StructuredBodyKey key, {
    bool allowBuffered = false,
  }) async {
    final row = await database
        .customSelect(
          'SELECT id, revision, base_version, base_blocks, body_version, '
          'body_blocks, updated_at, base_metadata, session_metadata, '
          'CASE WHEN text_buffer IS NULL THEN 0 ELSE 1 END AS has_text_buffer FROM structured_body_drafts '
          'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ?',
          variables: _keyVariables(key),
        )
        .getSingleOrNull();
    if (row == null) return null;
    if (!allowBuffered && row.read<int>('has_text_buffer') != 0) {
      throw const FormatException(
        'Local text buffer requires explicit recovery',
      );
    }
    final baseJson = row.read<String>('base_blocks');
    final bodyJson = row.read<String>('body_blocks');
    final baseMetadataJson = row.readNullable<String>('base_metadata');
    final sessionMetadataJson = row.readNullable<String>('session_metadata');
    final baseVersion = row.read<int>('base_version');
    final bodyVersion = row.read<int>('body_version');
    final rowId = row.read<int>('id');
    final revision = row.read<int>('revision');
    if (rowId <= 0 || revision <= 0) {
      throw const FormatException('Invalid local structured body revision');
    }
    return StructuredBodyRecovery(
      key: key,
      backendStorageKey: _backend,
      rowId: rowId,
      revision: revision,
      base: _decode(baseVersion, baseJson),
      body: _decode(bodyVersion, bodyJson),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
      baseStorageJson: baseJson,
      bodyStorageJson: bodyJson,
      baseMetadata: baseMetadataJson == null
          ? null
          : StructuredSessionMetadata.decode(baseMetadataJson),
      sessionMetadata: sessionMetadataJson == null
          ? null
          : StructuredSessionMetadata.decode(sessionMetadataJson),
      baseMetadataStorageJson: baseMetadataJson,
      sessionMetadataStorageJson: sessionMetadataJson,
    );
  }

  StructuredArticleDraft _decode(int version, String encoded) {
    // Check before parsing to avoid allocating an unbounded corrupted value.
    if (encoded.length > 1000000) {
      throw const FormatException('Structured body recovery is too large');
    }
    return StructuredArticleDraft.parse(
      version: version,
      blocks: jsonDecode(encoded),
    );
  }

  List<Variable<String>> _keyVariables(StructuredBodyKey key) => [
    Variable<String>(_backend),
    Variable<String>(key.userId),
    Variable<String>(key.articleId),
    Variable<String>(key.locale),
  ];

  @override
  Future<StructuredBodyRecovery?> create({
    required StructuredBodyKey key,
    required StructuredArticleDraft base,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? sessionMetadata,
  }) async {
    final baseMetadataJson = baseMetadata == null
        ? null
        : jsonEncode(baseMetadata.toJson());
    final sessionMetadataJson = sessionMetadata == null
        ? null
        : jsonEncode(sessionMetadata.toJson());
    final baseJson = jsonEncode(base.blocks);
    final bodyJson = jsonEncode(body.blocks);
    return database.transaction(() async {
      final inserted = await database.customUpdate(
        'INSERT INTO structured_body_drafts '
        '(backend, user_id, article_id, locale, revision, base_version, '
        'base_blocks, body_version, body_blocks, updated_at, base_metadata, session_metadata) '
        'VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(backend, user_id, article_id, locale) DO NOTHING',
        variables: [
          ..._keyVariables(key),
          Variable<int>(base.version),
          Variable<String>(baseJson),
          Variable<int>(body.version),
          Variable<String>(bodyJson),
          Variable<int>(updatedAt.microsecondsSinceEpoch),
          Variable<String>(baseMetadataJson),
          Variable<String>(sessionMetadataJson),
        ],
      );
      return inserted == 1 ? _load(key) : null;
    });
  }

  @override
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  }) => _replace(
    expected: expected,
    body: body,
    metadataJson: expected.sessionMetadataStorageJson,
    updatedAt: updatedAt,
  );

  @override
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  }) => _replace(
    expected: expected,
    body: body,
    metadataJson: jsonEncode(sessionMetadata.toJson()),
    updatedAt: updatedAt,
  );

  Future<StructuredBodyRecovery?> _replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required String? metadataJson,
    required DateTime updatedAt,
  }) async {
    final bodyJson = jsonEncode(body.blocks);
    return database.transaction(() async {
      final changed = await database.customUpdate(
        'UPDATE structured_body_drafts SET body_version = ?, body_blocks = ?, '
        'updated_at = ?, session_metadata = ?, revision = revision + 1 '
        'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ? '
        'AND backend = ? AND id = ? AND revision = ? AND base_version = ? AND base_blocks = ? '
        'AND body_version = ? AND body_blocks = ? AND updated_at = ? '
        'AND base_metadata IS ? AND session_metadata IS ? '
        'AND text_buffer IS NULL AND revision < 9223372036854775807',
        variables: [
          Variable<int>(body.version),
          Variable<String>(bodyJson),
          Variable<int>(updatedAt.microsecondsSinceEpoch),
          Variable<String>(metadataJson),
          ..._snapshotVariables(expected),
        ],
      );
      return changed == 1 ? _load(expected.key) : null;
    });
  }

  @override
  Future<bool> discard(StructuredBodyRecovery expected) async {
    final deleted = await database.customUpdate(
      'DELETE FROM structured_body_drafts '
      'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ? '
      'AND backend = ? AND id = ? AND revision = ? AND base_version = ? AND base_blocks = ? '
      'AND body_version = ? AND body_blocks = ? AND updated_at = ? '
      'AND base_metadata IS ? AND session_metadata IS ? AND text_buffer IS NULL',
      variables: _snapshotVariables(expected),
    );
    return deleted == 1;
  }

  @override
  Future<StructuredTextBufferRecovery?> loadTextBuffer(
    StructuredBodyKey key,
  ) async {
    return database.transaction(() async {
      final row = await database
          .customSelect(
            'SELECT substr(text_buffer, 1, 150001) AS text_buffer FROM structured_body_drafts '
            'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ?',
            variables: _keyVariables(key),
          )
          .getSingleOrNull();
      if (row == null) {
        return null;
      }
      final raw = row.readNullable<String>('text_buffer');
      if (raw == null) {
        return null;
      }
      final parent = await _load(key, allowBuffered: true);
      if (parent == null) {
        throw const FormatException('Missing parent recovery');
      }
      final buffer = StructuredTextBuffer.decode(raw);
      buffer.validateTarget(parent.body);
      return StructuredTextBufferRecovery(
        parent: parent,
        buffer: buffer,
        storageJson: raw,
      );
    });
  }

  @override
  Future<StructuredTextBufferRecovery?> createTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    buffer.validateTarget(expected.body);
    return _writeTextBuffer(
      expected: expected,
      previous: null,
      buffer: buffer,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<StructuredTextBufferRecovery?> replaceTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    _validateExpectedBuffer(expected);
    // Retargeting a buffer would abandon the previous intermediate input.
    if (buffer.blockId != expected.buffer.blockId) {
      throw ArgumentError('Text buffer target changed');
    }
    buffer.validateTarget(expected.parent.body);
    return _writeTextBuffer(
      expected: expected.parent,
      previous: expected.storageJson,
      buffer: buffer,
      updatedAt: updatedAt,
    );
  }

  Future<StructuredTextBufferRecovery?> _writeTextBuffer({
    required StructuredBodyRecovery expected,
    required String? previous,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    final encoded = buffer.encode();
    return database.transaction(() async {
      final changed = await database.customUpdate(
        'UPDATE structured_body_drafts SET text_buffer = ?, updated_at = ?, revision = revision + 1 '
        'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ? '
        'AND backend = ? AND id = ? AND revision = ? AND base_version = ? AND base_blocks = ? '
        'AND body_version = ? AND body_blocks = ? AND updated_at = ? '
        'AND base_metadata IS ? AND session_metadata IS ? AND text_buffer IS ? '
        'AND revision < 9223372036854775807',
        variables: [
          Variable<String>(encoded),
          Variable<int>(updatedAt.toUtc().microsecondsSinceEpoch),
          ..._snapshotVariables(expected),
          Variable<String>(previous),
        ],
      );
      if (changed != 1) {
        return null;
      }
      final parent = (await _load(expected.key, allowBuffered: true))!;
      return StructuredTextBufferRecovery(
        parent: parent,
        buffer: buffer,
        storageJson: encoded,
      );
    });
  }

  @override
  Future<StructuredBodyRecovery?> applyTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    _validateExpectedBuffer(expected);
    final body = expected.buffer.applyTo(expected.parent.body);
    return _finishTextBuffer(
      expected: expected,
      body: body,
      bodyJson: jsonEncode(body.blocks),
      updatedAt: updatedAt,
    );
  }

  @override
  Future<StructuredBodyRecovery?> discardTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    _validateExpectedBuffer(expected);
    return _finishTextBuffer(
      expected: expected,
      body: expected.parent.body,
      bodyJson: expected.parent.bodyStorageJson,
      updatedAt: updatedAt,
    );
  }

  void _validateExpectedBuffer(StructuredTextBufferRecovery expected) {
    final decoded = StructuredTextBuffer.decode(expected.storageJson);
    if (decoded.blockId != expected.buffer.blockId ||
        decoded.text != expected.buffer.text) {
      throw const FormatException('Buffer snapshot mismatch');
    }
    decoded.validateTarget(expected.parent.body);
  }

  Future<StructuredBodyRecovery?> _finishTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredArticleDraft body,
    required String bodyJson,
    required DateTime updatedAt,
  }) async {
    return database.transaction(() async {
      final changed = await database.customUpdate(
        'UPDATE structured_body_drafts SET text_buffer = NULL, body_version = ?, body_blocks = ?, '
        'updated_at = ?, revision = revision + 1 '
        'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ? '
        'AND backend = ? AND id = ? AND revision = ? AND base_version = ? AND base_blocks = ? '
        'AND body_version = ? AND body_blocks = ? AND updated_at = ? '
        'AND base_metadata IS ? AND session_metadata IS ? AND text_buffer IS ? '
        'AND revision < 9223372036854775807',
        variables: [
          Variable<int>(body.version),
          Variable<String>(bodyJson),
          Variable<int>(updatedAt.toUtc().microsecondsSinceEpoch),
          ..._snapshotVariables(expected.parent),
          Variable<String>(expected.storageJson),
        ],
      );
      return changed == 1 ? _load(expected.parent.key) : null;
    });
  }

  List<Variable> _snapshotVariables(StructuredBodyRecovery expected) => [
    ..._keyVariables(expected.key),
    Variable<String>(expected.backendStorageKey),
    Variable<int>(expected.rowId),
    Variable<int>(expected.revision),
    Variable<int>(expected.base.version),
    Variable<String>(expected.baseStorageJson),
    Variable<int>(expected.body.version),
    Variable<String>(expected.bodyStorageJson),
    Variable<int>(expected.updatedAt.microsecondsSinceEpoch),
    Variable<String>(expected.baseMetadataStorageJson),
    Variable<String>(expected.sessionMetadataStorageJson),
  ];
}
