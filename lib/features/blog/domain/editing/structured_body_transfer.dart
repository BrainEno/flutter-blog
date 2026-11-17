import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:belog/features/blog/domain/editing/structured_history_patch.dart';

/// A one-session body capture. Consumers must immediately drop it on identity,
/// body or route invalidation; already handed-out immutable objects cannot be
/// revoked. A history generation authorizes no write by itself.
final class StructuredTransferCapture {
  const StructuredTransferCapture._({
    required this.body,
    required this.historyGeneration,
  });
  final StructuredArticleDraft body;
  final int? historyGeneration;

  /// A failed or conflicting save can still be exported as an in-memory body.
  /// Import is restricted to the editing phase and requires a live timeline.
  static StructuredTransferCapture? take(LocalStructuredSession session) {
    final state = session.state;
    if (!_visible(state.phase) || state.body == null) return null;
    final history = session.captureBodyHistory();
    if (!identical(session.state, state)) return null;
    if (state.phase == LocalStructuredPhase.editing && history == null) {
      return null;
    }
    return StructuredTransferCapture._(
      body: state.body!,
      historyGeneration: history?.generation,
    );
  }

  bool visibleIn(LocalStructuredSession session) {
    final state = session.state;
    return _visible(state.phase) && identical(state.body, body);
  }

  bool importableIn(LocalStructuredSession session) {
    if (!visibleIn(session) || historyGeneration == null) return false;
    final view = session.captureBodyHistory();
    return view != null &&
        view.generation == historyGeneration &&
        identical(view.current.body, body);
  }
}

bool _visible(LocalStructuredPhase phase) =>
    phase == LocalStructuredPhase.editing ||
    phase == LocalStructuredPhase.saveFailed ||
    phase == LocalStructuredPhase.conflict;

enum StructuredTransferApplyResult { accepted, unchanged, stale, invalid }

/// A read-only comparison of a validated imported body and the exact captured
/// local body. It is not a merge: confirmed application replaces the body and
/// retains the current session metadata. No network or clipboard dependency.
final class StructuredTransferPreview {
  StructuredTransferPreview._({
    required this.capture,
    required this.imported,
    required this.comparison,
  });
  final StructuredTransferCapture capture;
  final StructuredArticleDraft imported;
  final StructuredDocumentComparison comparison;

  static StructuredTransferPreview? create({
    required LocalStructuredSession session,
    required StructuredTransferCapture capture,
    required StructuredArticleDraft imported,
  }) {
    if (!capture.importableIn(session)) return null;
    return StructuredTransferPreview._(
      capture: capture,
      imported: imported,
      comparison: StructuredDocumentComparison.between(capture.body, imported),
    );
  }

  /// Construct a read-only, all-or-nothing proposal for selected shared
  /// blocks. Missing, unchanged and invalid selections fail closed. The plan
  /// is advisory; applySelected reconstructs it after rechecking the fence.
  StructuredHistoryPatch prepareSelected(Set<String> ids) =>
      StructuredHistoryPatch.prepare(
        current: capture.body,
        source: imported,
        blockIds: ids,
      );

  StructuredTransferApplyResult applySelected(
    LocalStructuredSession session,
    Set<String> ids,
  ) {
    if (!capture.importableIn(session)) {
      return StructuredTransferApplyResult.stale;
    }
    try {
      final patch = prepareSelected(ids);
      if (!capture.importableIn(session)) {
        return StructuredTransferApplyResult.stale;
      }
      return session.edit((body) => patch.result)
          ? StructuredTransferApplyResult.accepted
          : StructuredTransferApplyResult.stale;
    } on FormatException {
      return StructuredTransferApplyResult.invalid;
    } on ArgumentError {
      return StructuredTransferApplyResult.invalid;
    }
  }

  /// Recheck both fence and body/timeline after any confirmation or async work.
  /// An accepted result means queued, never durable or published. The existing
  /// local writer's CAS and failure handling remain the sole persistence path.
  StructuredTransferApplyResult apply(LocalStructuredSession session) {
    if (!capture.importableIn(session)) {
      return StructuredTransferApplyResult.stale;
    }
    if (!comparison.hasChanges) return StructuredTransferApplyResult.unchanged;
    final accepted = session.edit((body) => imported);
    return accepted
        ? StructuredTransferApplyResult.accepted
        : StructuredTransferApplyResult.stale;
  }
}
