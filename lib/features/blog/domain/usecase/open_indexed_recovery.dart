import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';

/// Open a listed local row without waiting for or contacting the server. The
/// existing session still asks before recovery and applies all normal CAS and
/// identity checks. A deleted/recreated row is not the one the user selected.
LocalStructuredSession openIndexedRecovery({
  required StructuredRecoveryIndexEntry entry,
  required NowaveSessionFence fence,
  required OpenStructuredEditingSession opener,
}) {
  final key = entry.key;
  if (key == null || key.userId != fence.userId || entry.rowId <= 0) {
    throw ArgumentError('Invalid recovery selection');
  }
  return LocalStructuredSession(
    key: key,
    fence: fence,
    opener: OpenStructuredEditingSession(
      reader: const _OfflineReader(),
      store: opener.store is StructuredTextSessionStore
          ? _SelectedTextRowStore(
              opener.store as StructuredTextSessionStore,
              entry.rowId,
            )
          : _SelectedRowStore(opener.store, entry.rowId),
      identity: opener.identity,
    ),
  );
}

class _OfflineReader implements StructuredEditionReader {
  const _OfflineReader();
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async => const StructuredEditionReadResult.failed(
    StructuredEditionReadStatus.unavailable,
  );
}

/// Restrict the initial read to the selected incarnation, without changing the
/// underlying store's exact-token compare-and-swap for any subsequent write.
class _SelectedRowStore implements StructuredBodyRecoveryStore {
  const _SelectedRowStore(this.inner, this.rowId);
  final StructuredBodyRecoveryStore inner;
  final int rowId;

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) async {
    final row = await inner.load(key);
    if (row == null || row.rowId != rowId) {
      throw StateError('Recovery selection changed');
    }
    return row;
  }

  @override
  Future<StructuredBodyRecovery?> create({
    required StructuredBodyKey key,
    required StructuredArticleDraft base,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? sessionMetadata,
  }) => inner.create(
    key: key,
    base: base,
    body: body,
    updatedAt: updatedAt,
    baseMetadata: baseMetadata,
    sessionMetadata: sessionMetadata,
  );
  @override
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  }) => inner.replace(expected: expected, body: body, updatedAt: updatedAt);
  @override
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  }) => inner.replaceSession(
    expected: expected,
    body: body,
    sessionMetadata: sessionMetadata,
    updatedAt: updatedAt,
  );
  @override
  Future<bool> discard(StructuredBodyRecovery expected) =>
      inner.discard(expected);
}

/// Preserve the combined backend-scoped capability through the selected-row
/// wrapper. The first buffer read also enforces the selected incarnation.
class _SelectedTextRowStore extends _SelectedRowStore
    implements StructuredTextSessionStore {
  const _SelectedTextRowStore(this.textStore, int rowId)
    : super(textStore, rowId);
  final StructuredTextSessionStore textStore;

  @override
  Future<StructuredTextBufferRecovery?> loadTextBuffer(
    StructuredBodyKey key,
  ) async {
    final value = await textStore.loadTextBuffer(key);
    if (value != null && value.parent.rowId != rowId) {
      throw StateError('Recovery selection changed');
    }
    return value;
  }

  @override
  Future<StructuredTextBufferRecovery?> createTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) => textStore.createTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );
  @override
  Future<StructuredTextBufferRecovery?> replaceTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) => textStore.replaceTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );
  @override
  Future<StructuredBodyRecovery?> applyTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => textStore.applyTextBuffer(expected: expected, updatedAt: updatedAt);
  @override
  Future<StructuredBodyRecovery?> discardTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => textStore.discardTextBuffer(expected: expected, updatedAt: updatedAt);
}
