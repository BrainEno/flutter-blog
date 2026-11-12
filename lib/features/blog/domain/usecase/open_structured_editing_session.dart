import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';

/// Returns remote and local snapshots separately. It does not apply a read to
/// a controller, write to SQLite, or choose a recovery policy for the author.
/// An unreadable local snapshot blocks automatic initialization from remote.
enum StructuredSessionOpenStatus { ready, localReadFailed, obsolete }

class StructuredSessionOpenResult {
  const StructuredSessionOpenResult._(this.status, this.remote, this.local);
  const StructuredSessionOpenResult.obsolete()
    : this._(StructuredSessionOpenStatus.obsolete, null, null);
  const StructuredSessionOpenResult.localReadFailed(
    StructuredEditionReadResult remote,
  ) : this._(StructuredSessionOpenStatus.localReadFailed, remote, null);
  const StructuredSessionOpenResult.ready(
    StructuredEditionReadResult remote,
    StructuredBodyRecovery? local,
  ) : this._(StructuredSessionOpenStatus.ready, remote, local);

  final StructuredSessionOpenStatus status;
  final StructuredEditionReadResult? remote;
  final StructuredBodyRecovery? local;
}

/// Local/account/request fences around the two independent reads. [isCurrent]
/// must become false when a route is disposed or the user edits during a load.
/// Callers must check it again when applying a result to UI state. A later local
/// save must still use the snapshot's compare-and-swap token, not overwrite it.
class OpenStructuredEditingSession {
  const OpenStructuredEditingSession({
    required this.reader,
    required this.store,
    required this.identity,
  });
  final StructuredEditionReader reader;
  final StructuredBodyRecoveryStore store;
  final NowaveSessionIdentity identity;

  Future<StructuredSessionOpenResult> call({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
    required bool Function() isCurrent,
  }) async {
    bool active() =>
        isCurrent() &&
        key.userId == fence.userId &&
        identity.activeUserId == fence.userId &&
        identity.sessionGeneration == fence.generation &&
        !(identity.accessToken?.isEmpty ?? true);
    if (!active()) return const StructuredSessionOpenResult.obsolete();
    final remote = await reader.read(key: key, fence: fence);
    if (!active() ||
        remote.status == StructuredEditionReadStatus.sessionChanged) {
      return const StructuredSessionOpenResult.obsolete();
    }
    try {
      final local = await store.load(key);
      if (!active()) return const StructuredSessionOpenResult.obsolete();
      return StructuredSessionOpenResult.ready(remote, local);
    } on Object {
      if (!active()) return const StructuredSessionOpenResult.obsolete();
      return StructuredSessionOpenResult.localReadFailed(remote);
    }
  }
}
