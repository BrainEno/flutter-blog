import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';

enum StructuredRecoveryListStatus { ready, unavailable, obsolete }

class StructuredRecoveryListResult {
  const StructuredRecoveryListResult(this.status, [this.page]);
  final StructuredRecoveryListStatus status;
  final StructuredRecoveryIndexPage? page;
}

/// A local index is private even when the network is unavailable. The fence
/// protects both before and after the async query; it is not server authority.
class ListStructuredRecoveries {
  const ListStructuredRecoveries({
    required this.catalog,
    required this.identity,
  });
  final StructuredRecoveryCatalog catalog;
  final NowaveSessionIdentity identity;

  bool isActive(NowaveSessionFence fence) =>
      fence.userId.isNotEmpty &&
      fence.userId == fence.userId.trim() &&
      identity.activeUserId == fence.userId &&
      identity.sessionGeneration == fence.generation &&
      !(identity.accessToken?.isEmpty ?? true);

  Future<StructuredRecoveryListResult> call({
    required NowaveSessionFence fence,
    required bool Function() isCurrent,
    int? afterRowId,
  }) async {
    bool active() => isCurrent() && isActive(fence);
    if (!active()) {
      return const StructuredRecoveryListResult(
        StructuredRecoveryListStatus.obsolete,
      );
    }
    try {
      final page = await catalog.page(
        userId: fence.userId,
        afterRowId: afterRowId,
      );
      if (!active()) {
        return const StructuredRecoveryListResult(
          StructuredRecoveryListStatus.obsolete,
        );
      }
      if (!_validPage(page, fence.userId, afterRowId)) {
        return const StructuredRecoveryListResult(
          StructuredRecoveryListStatus.unavailable,
        );
      }
      return StructuredRecoveryListResult(
        StructuredRecoveryListStatus.ready,
        page,
      );
    } on Object {
      if (!active()) {
        return const StructuredRecoveryListResult(
          StructuredRecoveryListStatus.obsolete,
        );
      }
      return const StructuredRecoveryListResult(
        StructuredRecoveryListStatus.unavailable,
      );
    }
  }
}

// Defensively reject invalid or cross-account projections rather than display
// them. A cursor is local-only and must advance in strict row order.
bool _validPage(
  StructuredRecoveryIndexPage page,
  String userId,
  int? afterRowId,
) {
  if (page.entries.length > 25 || (afterRowId != null && afterRowId <= 0)) {
    return false;
  }
  var previous = afterRowId ?? 0;
  for (final entry in page.entries) {
    if (entry.rowId <= previous ||
        (entry.key != null && entry.key!.userId != userId)) {
      return false;
    }
    previous = entry.rowId;
  }
  return page.nextCursor == null ||
      (page.entries.isNotEmpty && page.nextCursor == previous);
}
