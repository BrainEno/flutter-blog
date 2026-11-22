import 'package:belog/features/blog/domain/editing/local_structured_rich_text_session.dart';
import 'package:belog/features/blog/domain/editing/local_structured_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';

// The values a `LocalStructuredSession` reports. Kept apart from the session
// so the state machine reads on its own; the session library re-exports them.

/// Local-only state. Neither a successful read nor a saved local revision
/// grants permission to publish or establishes an atomic server version.
enum LocalStructuredPhase {
  initial,
  opening,
  recoveryChoice,
  editing,
  unavailable,
  localReadFailed,
  saveFailed,
  conflict,
  cancelled,
  invalidated,
  closed,
}

/// A comparison is advisory and deliberately does not claim the server has
/// not changed: server fields not represented in local metadata may differ.
enum StructuredBaseComparison {
  noLocalBase,
  remoteUnavailable,
  bodyDiffers,
  metadataUnknown,
  metadataDiffers,
  representedFieldsMatch,
}

/// Immutable view of the session. Previously obtained values cannot be
/// revoked by the session; consumers must discard their own references on an
/// identity event. New states after invalidation never include private data.
class LocalStructuredState {
  const LocalStructuredState({
    required this.phase,
    this.body,
    this.baseBody,
    this.metadata,
    this.remoteStatus,
    this.baseComparison,
    this.saving = false,
    this.hasUnsavedChanges = false,
    this.recoveryAvailable = false,
  });

  final LocalStructuredPhase phase;

  /// The original snapshot for this local session, not a fresh server read.
  /// It is cleared with all private state when the account fence invalidates.
  final StructuredArticleDraft? body;
  final StructuredArticleDraft? baseBody;
  final StructuredSessionMetadata? metadata;
  final StructuredEditionReadStatus? remoteStatus;
  final StructuredBaseComparison? baseComparison;
  final bool saving;
  final bool hasUnsavedChanges;
  final bool recoveryAvailable;
}

/// Outcome of restoring the exact content of one existing block from a
/// captured history entry. No outcome implies a durable save or remote write.
enum LocalHistoryBlockRestoreResult { accepted, unchanged, stale, invalid }

enum LocalStructuredFlushResult {
  saved,
  failed,
  conflict,
  notReady,
  obsolete,
  closed,
}

enum LocalTextHandoffStatus {
  ready,
  unsupportedStore,
  invalidTarget,
  notReady,
  failed,
  conflict,
  obsolete,
}

/// On [LocalTextHandoffStatus.ready] the body session is closed. A concurrent
/// close or identity change may also close it while returning obsolete. The
/// returned session requires explicit recovery and refuses any changed row.
class LocalTextHandoffResult {
  const LocalTextHandoffResult(this.status, [this.session]);
  final LocalTextHandoffStatus status;
  final LocalStructuredTextSession? session;
}

/// A rich handoff uses the same status vocabulary as the plain editor, but
/// returns a coordinator for one explicitly captured formatted target.
class LocalRichTextHandoffResult {
  const LocalRichTextHandoffResult(this.status, [this.session]);
  final LocalTextHandoffStatus status;
  final LocalStructuredRichTextSession? session;
}
