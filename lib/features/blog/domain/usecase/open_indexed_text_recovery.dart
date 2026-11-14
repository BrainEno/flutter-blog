import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/local_structured_text_session.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';

enum IndexedTextRecoveryStatus {
  ready,
  noBuffer,
  changed,
  unavailable,
  obsolete,
}

class IndexedTextRecoveryResult {
  const IndexedTextRecoveryResult(this.status, [this.session]);
  final IndexedTextRecoveryStatus status;
  final LocalStructuredTextSession? session;
}

/// Resolve an explicitly selected local index entry without a remote request.
/// Callers must retain their own route-generation fence and supply an identity
/// that invalidates when the account or route changes. The session rereads the
/// exact raw buffer and parent token, and still requires a recovery decision.
/// Missing, damaged or future-format data is never repaired or overwritten.
class OpenIndexedTextRecovery {
  const OpenIndexedTextRecovery({required this.store, required this.identity});
  final StructuredTextSessionStore store;
  final NowaveSessionIdentity identity;

  Future<IndexedTextRecoveryResult> call({
    required StructuredRecoveryIndexEntry entry,
    required NowaveSessionFence fence,
    required bool Function() isCurrent,
  }) async {
    bool active() =>
        isCurrent() &&
        entry.key?.userId == fence.userId &&
        identity.activeUserId == fence.userId &&
        identity.sessionGeneration == fence.generation &&
        !(identity.accessToken?.isEmpty ?? true);
    if (!active()) {
      return const IndexedTextRecoveryResult(
        IndexedTextRecoveryStatus.obsolete,
      );
    }
    if (entry.rowId <= 0 || entry.key == null) {
      return const IndexedTextRecoveryResult(IndexedTextRecoveryStatus.changed);
    }
    try {
      final saved = await store.loadTextBuffer(entry.key!);
      if (!active()) {
        return const IndexedTextRecoveryResult(
          IndexedTextRecoveryStatus.obsolete,
        );
      }
      if (saved == null) {
        return const IndexedTextRecoveryResult(
          IndexedTextRecoveryStatus.noBuffer,
        );
      }
      if (saved.parent.rowId != entry.rowId ||
          saved.parent.key.userId != entry.key!.userId ||
          saved.parent.key.articleId != entry.key!.articleId ||
          saved.parent.key.locale != entry.key!.locale) {
        return const IndexedTextRecoveryResult(
          IndexedTextRecoveryStatus.changed,
        );
      }
      final session = LocalStructuredTextSession(
        key: entry.key!,
        selectedRowId: entry.rowId,
        blockId: saved.buffer.blockId,
        fence: fence,
        identity: identity,
        store: store,
        expectedBufferedRecovery: saved,
      );
      if (!active()) {
        await session.close();
        return const IndexedTextRecoveryResult(
          IndexedTextRecoveryStatus.obsolete,
        );
      }
      return IndexedTextRecoveryResult(
        IndexedTextRecoveryStatus.ready,
        session,
      );
    } on Object {
      return IndexedTextRecoveryResult(
        active()
            ? IndexedTextRecoveryStatus.unavailable
            : IndexedTextRecoveryStatus.obsolete,
      );
    }
  }
}
