import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/local_structured_rich_text_session.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_session_store.dart';

enum IndexedRichTextRecoveryStatus {
  ready,
  noBuffer,
  changed,
  unavailable,
  obsolete,
}

class IndexedRichTextRecoveryResult {
  const IndexedRichTextRecoveryResult(this.status, [this.session]);
  final IndexedRichTextRecoveryStatus status;
  final LocalStructuredRichTextSession? session;
}

/// Resolve an explicitly selected local catalog entry without network access.
/// The caller must fence its route and supply an identity that invalidates on
/// route changes. Open still rereads the complete snapshot and requires consent.
class OpenIndexedRichTextRecovery {
  const OpenIndexedRichTextRecovery({
    required this.store,
    required this.identity,
  });
  final StructuredRichTextSessionStore store;
  final NowaveSessionIdentity identity;

  Future<IndexedRichTextRecoveryResult> call({
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
      return const IndexedRichTextRecoveryResult(
        IndexedRichTextRecoveryStatus.obsolete,
      );
    }
    if (entry.rowId <= 0 || entry.key == null) {
      return const IndexedRichTextRecoveryResult(
        IndexedRichTextRecoveryStatus.changed,
      );
    }
    try {
      final saved = await store.loadRichTextBuffer(entry.key!);
      if (!active()) {
        return const IndexedRichTextRecoveryResult(
          IndexedRichTextRecoveryStatus.obsolete,
        );
      }
      if (saved == null) {
        return const IndexedRichTextRecoveryResult(
          IndexedRichTextRecoveryStatus.noBuffer,
        );
      }
      if (saved.parent.rowId != entry.rowId ||
          saved.parent.key.userId != entry.key!.userId ||
          saved.parent.key.articleId != entry.key!.articleId ||
          saved.parent.key.locale != entry.key!.locale) {
        return const IndexedRichTextRecoveryResult(
          IndexedRichTextRecoveryStatus.changed,
        );
      }
      final session = LocalStructuredRichTextSession(
        key: entry.key!,
        selectedRowId: entry.rowId,
        blockId: saved.buffer.blockId,
        itemIndex: saved.buffer.itemIndex,
        fence: fence,
        identity: identity,
        store: store,
        expectedBufferedRecovery: saved,
      );
      if (!active()) {
        await session.close();
        return const IndexedRichTextRecoveryResult(
          IndexedRichTextRecoveryStatus.obsolete,
        );
      }
      return IndexedRichTextRecoveryResult(
        IndexedRichTextRecoveryStatus.ready,
        session,
      );
    } on Object {
      return IndexedRichTextRecoveryResult(
        active()
            ? IndexedRichTextRecoveryStatus.unavailable
            : IndexedRichTextRecoveryStatus.obsolete,
      );
    }
  }
}
