import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:drift/drift.dart';

/// SQLite body recovery for existing article editions. Atomic local revision
/// comparisons protect multiple store instances/editors; they are not a
/// server-side version check and do not make remote publication safe.
class SqliteStructuredBodyRecoveryStore implements StructuredBodyRecoveryStore {
  SqliteStructuredBodyRecoveryStore(this.database, {required Uri apiBaseUrl})
    : _backend = backendKeyOf(apiBaseUrl);

  final AppDatabase database;
  final String _backend;

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) => _load(key);

  Future<StructuredBodyRecovery?> _load(StructuredBodyKey key) async {
    final row = await database
        .customSelect(
          'SELECT id, revision, base_version, base_blocks, body_version, '
          'body_blocks, updated_at, base_metadata, session_metadata FROM structured_body_drafts '
          'WHERE backend = ? AND user_id = ? AND article_id = ? AND locale = ?',
          variables: _keyVariables(key),
        )
        .getSingleOrNull();
    if (row == null) return null;
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
        'AND revision < 9223372036854775807',
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
      'AND base_metadata IS ? AND session_metadata IS ?',
      variables: _snapshotVariables(expected),
    );
    return deleted == 1;
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
