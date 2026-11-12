import 'dart:async';
import 'dart:convert';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';

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
    this.metadata,
    this.remoteStatus,
    this.baseComparison,
    this.saving = false,
    this.hasUnsavedChanges = false,
    this.recoveryAvailable = false,
  });

  final LocalStructuredPhase phase;
  final StructuredArticleDraft? body;
  final StructuredSessionMetadata? metadata;
  final StructuredEditionReadStatus? remoteStatus;
  final StructuredBaseComparison? baseComparison;
  final bool saving;
  final bool hasUnsavedChanges;
  final bool recoveryAvailable;
}

enum LocalStructuredFlushResult {
  saved,
  failed,
  conflict,
  notReady,
  obsolete,
  closed,
}

class _Edit {
  const _Edit(this.body, this.metadata);
  final StructuredArticleDraft body;
  final StructuredSessionMetadata? metadata;
}

/// One owner's one-language local-only editing session. This object contains
/// no remote write or publish operation. Changes accepted while the fence is
/// valid are serialized and coalesced; an already accepted write may finish
/// under its original immutable key after sign-out, but never under the new
/// account. A CAS conflict or storage error stops the writer rather than
/// retrying against a newer snapshot. The latest unsaved edit remains visible
/// while the original session is active.
///
/// [close] waits for accepted writes and reports failures; callers must not
/// silently navigate away when it returns false. If the OS kills the process,
/// or storage fails as an account is replaced, in-memory edits may still be
/// lost: a local write is durable only after [flush] reports saved.
class LocalStructuredSession {
  LocalStructuredSession({
    required this.key,
    required this.fence,
    required this.opener,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _identitySubscription = opener.identity.identityChanges.listen((_) {
      _checkIdentity();
    });
  }

  final StructuredBodyKey key;
  final NowaveSessionFence fence;
  final OpenStructuredEditingSession opener;

  // Use exactly the same identity and backend-scoped store as the opener. A
  // caller cannot accidentally load from one namespace and save to another.
  NowaveSessionIdentity get identity => opener.identity;
  StructuredBodyRecoveryStore get store => opener.store;
  final DateTime Function() _now;
  final _changes = StreamController<LocalStructuredState>.broadcast(sync: true);
  late final StreamSubscription<void> _identitySubscription;
  LocalStructuredState _state = const LocalStructuredState(
    phase: LocalStructuredPhase.initial,
  );
  StructuredEditionReadResult? _remote;
  StructuredBodyRecovery? _recovery;
  StructuredArticleDraft? _base;
  StructuredSessionMetadata? _baseMetadata;
  _Edit? _pending;
  Future<void>? _writer;
  bool _notifying = false;
  bool _notificationPending = false;
  bool _writeHalted = false;
  bool _discarding = false;
  bool _closing = false;
  bool _invalidated = false;
  int _openGeneration = 0;

  Stream<LocalStructuredState> get changes => _changes.stream;

  LocalStructuredState get state {
    _checkIdentity();
    return _state;
  }

  bool get _matchesIdentity =>
      key.userId == fence.userId &&
      identity.activeUserId == fence.userId &&
      identity.sessionGeneration == fence.generation &&
      !(identity.accessToken?.isEmpty ?? true);

  bool _checkIdentity() {
    if (!_invalidated &&
        !_matchesIdentity &&
        _state.phase != LocalStructuredPhase.closed) {
      _invalidated = true;
      _openGeneration++;
      _remote = null;
      // The writer owns admitted edits under the original key. Keep its CAS
      // token and base privately until it finishes, never in the public state.
      _set(const LocalStructuredState(phase: LocalStructuredPhase.invalidated));
    }
    return !_invalidated &&
        _matchesIdentity &&
        _state.phase != LocalStructuredPhase.closed;
  }

  void _set(LocalStructuredState next) {
    _state = next;
    if (_changes.isClosed) return;
    if (_notifying) {
      // A synchronous observer can edit, close or switch accounts. Emit only
      // the latest nested state once the current broadcast finishes.
      _notificationPending = true;
      return;
    }
    _notifying = true;
    try {
      do {
        _notificationPending = false;
        _changes.add(_state);
      } while (_notificationPending && !_changes.isClosed);
    } finally {
      _notifying = false;
    }
  }

  /// Can only be called once. Local recovery always requires a decision, even
  /// when remote is unavailable or appears to match its original base.
  Future<void> open() async {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalStructuredPhase.initial) {
      return;
    }
    final generation = ++_openGeneration;
    _set(const LocalStructuredState(phase: LocalStructuredPhase.opening));
    if (_closing || !_checkIdentity() || generation != _openGeneration) return;
    try {
      final result = await opener(
        key: key,
        fence: fence,
        isCurrent: () =>
            !_closing &&
            !_invalidated &&
            generation == _openGeneration &&
            _matchesIdentity,
      );
      if (!_checkIdentity() || generation != _openGeneration) return;
      if (result.status == StructuredSessionOpenStatus.obsolete) {
        _invalidated = true;
        _set(
          const LocalStructuredState(phase: LocalStructuredPhase.invalidated),
        );
        return;
      }
      final editionKey = result.remote?.edition?.key;
      final recoveryKey = result.local?.key;
      if ((editionKey != null && !_sameKey(editionKey, key)) ||
          (recoveryKey != null && !_sameKey(recoveryKey, key))) {
        _set(
          const LocalStructuredState(
            phase: LocalStructuredPhase.localReadFailed,
          ),
        );
        return;
      }
      _remote = result.remote;
      if (result.status == StructuredSessionOpenStatus.localReadFailed) {
        _set(
          LocalStructuredState(
            phase: LocalStructuredPhase.localReadFailed,
            remoteStatus: _remote?.status,
          ),
        );
        return;
      }
      _recovery = result.local;
      if (_recovery != null) {
        _set(
          LocalStructuredState(
            phase: LocalStructuredPhase.recoveryChoice,
            body: _recovery!.body,
            metadata: _recovery!.sessionMetadata,
            remoteStatus: _remote?.status,
            baseComparison: _compareBase(_recovery!, _remote),
            recoveryAvailable: true,
          ),
        );
      } else {
        _useRemote();
      }
    } on Object {
      if (!_checkIdentity() || generation != _openGeneration) return;
      _set(
        const LocalStructuredState(phase: LocalStructuredPhase.localReadFailed),
      );
    }
  }

  void _useRemote() {
    final edition = _remote?.edition;
    if (edition == null) {
      _set(
        LocalStructuredState(
          phase: LocalStructuredPhase.unavailable,
          remoteStatus: _remote?.status,
        ),
      );
      return;
    }
    _base = edition.body;
    _baseMetadata = edition.metadata;
    _set(
      LocalStructuredState(
        phase: LocalStructuredPhase.editing,
        body: edition.body,
        metadata: edition.metadata,
        remoteStatus: _remote?.status,
        baseComparison: StructuredBaseComparison.noLocalBase,
      ),
    );
  }

  /// Explicitly adopt the stored local revision; no data is written here.
  bool resumeRecovery() {
    if (!_checkIdentity() ||
        _closing ||
        _discarding ||
        _state.phase != LocalStructuredPhase.recoveryChoice) {
      return false;
    }
    final recovery = _recovery!;
    _base = recovery.base;
    _baseMetadata = recovery.baseMetadata;
    _set(
      LocalStructuredState(
        phase: LocalStructuredPhase.editing,
        body: recovery.body,
        metadata: recovery.sessionMetadata,
        remoteStatus: _remote?.status,
        baseComparison: _state.baseComparison,
        recoveryAvailable: true,
      ),
    );
    return true;
  }

  /// Cancel without deleting or overwriting the stored revision.
  bool cancelRecovery() {
    if (!_checkIdentity() ||
        _closing ||
        _discarding ||
        _state.phase != LocalStructuredPhase.recoveryChoice) {
      return false;
    }
    _remote = null;
    _recovery = null;
    _set(const LocalStructuredState(phase: LocalStructuredPhase.cancelled));
    return true;
  }

  /// Delete only the exact revision shown in the decision. Confirmation must
  /// be obtained by the caller; dismissal is represented by `false`.
  Future<bool> discardRecovery({required bool confirmed}) async {
    if (!confirmed ||
        !_checkIdentity() ||
        _closing ||
        _discarding ||
        _state.phase != LocalStructuredPhase.recoveryChoice) {
      return false;
    }
    final recovery = _recovery!;
    _discarding = true;
    try {
      final deleted = await store.discard(recovery);
      if (!_checkIdentity()) return false;
      if (!deleted) {
        _set(
          LocalStructuredState(
            phase: LocalStructuredPhase.conflict,
            remoteStatus: _remote?.status,
            recoveryAvailable: true,
          ),
        );
        return false;
      }
      _recovery = null;
      _useRemote();
      return true;
    } on Object {
      if (_checkIdentity()) {
        _set(
          LocalStructuredState(
            phase: LocalStructuredPhase.localReadFailed,
            remoteStatus: _remote?.status,
            recoveryAvailable: true,
          ),
        );
      }
      return false;
    } finally {
      _discarding = false;
    }
  }

  /// Apply an immutable, already validated operation synchronously. Invalid
  /// operations throw before state changes or writes. Each accepted snapshot
  /// is queued immediately; rapid edits coalesce behind the in-flight write.
  bool edit(StructuredArticleDraft Function(StructuredArticleDraft) operation) {
    if (!_canEdit()) return false;
    final before = _state;
    final next = operation(before.body!);
    // An operation can synchronously trigger a route or identity change, or
    // even another edit. Never resurrect its stale body after that event.
    if (!_canEdit() || !identical(_state, before)) return false;
    return _accept(_Edit(next, before.metadata));
  }

  /// Replace metadata intentionally. Null is not an implicit reset: older
  /// recovery rows with unknown metadata stay unknown unless explicitly set.
  bool editMetadata(StructuredSessionMetadata metadata) {
    if (!_canEdit()) return false;
    return _accept(_Edit(_state.body!, metadata));
  }

  bool _canEdit() =>
      _checkIdentity() &&
      !_closing &&
      (_state.phase == LocalStructuredPhase.editing) &&
      !_discarding;

  bool _accept(_Edit edit) {
    _pending = edit;
    _startWriter();
    // A custom store can synchronously trigger an identity change when the
    // operation starts. The admitted write keeps its old key, but its state
    // must never become visible to the replacement account.
    if (!_checkIdentity() || _closing) return true;
    _set(
      LocalStructuredState(
        phase: LocalStructuredPhase.editing,
        body: edit.body,
        metadata: edit.metadata,
        remoteStatus: _state.remoteStatus,
        baseComparison: _state.baseComparison,
        recoveryAvailable: _recovery != null,
        saving: true,
        hasUnsavedChanges: true,
      ),
    );
    return true;
  }

  void _startWriter() {
    if (_writer != null || _pending == null) return;
    final done = Completer<void>();
    _writer = done.future;
    unawaited(
      _drain().whenComplete(() {
        _writer = null;
        if (_pending != null && !_writeHalted) _startWriter();
        done.complete();
      }),
    );
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final edit = _pending!;
      _pending = null;
      try {
        final expected = _recovery;
        final saved = expected == null
            ? await store.create(
                key: key,
                base: _base!,
                body: edit.body,
                updatedAt: _now().toUtc(),
                baseMetadata: _baseMetadata,
                sessionMetadata: edit.metadata,
              )
            : edit.metadata == null
            ? await store.replace(
                expected: expected,
                body: edit.body,
                updatedAt: _now().toUtc(),
              )
            : await store.replaceSession(
                expected: expected,
                body: edit.body,
                sessionMetadata: edit.metadata!,
                updatedAt: _now().toUtc(),
              );
        if (saved == null) {
          _pending ??= edit;
          _writeHalted = true;
          _showWriteFailure(LocalStructuredPhase.conflict);
          return;
        }
        _recovery = saved;
      } on Object {
        _pending ??= edit;
        _writeHalted = true;
        _showWriteFailure(LocalStructuredPhase.saveFailed);
        return;
      }
    }
    if (_checkIdentity()) {
      _set(
        LocalStructuredState(
          phase: LocalStructuredPhase.editing,
          body: _state.body,
          metadata: _state.metadata,
          remoteStatus: _state.remoteStatus,
          baseComparison: _state.baseComparison,
          recoveryAvailable: true,
        ),
      );
    }
  }

  void _showWriteFailure(LocalStructuredPhase phase) {
    if (!_checkIdentity()) return;
    _set(
      LocalStructuredState(
        phase: phase,
        body: _state.body,
        metadata: _state.metadata,
        remoteStatus: _state.remoteStatus,
        baseComparison: _state.baseComparison,
        recoveryAvailable: _recovery != null,
        hasUnsavedChanges: true,
      ),
    );
  }

  /// Retry only storage failures. A failed transaction might actually have
  /// committed: the original CAS then reports conflict rather than overwriting.
  bool retrySave() {
    if (!_checkIdentity() ||
        _state.phase != LocalStructuredPhase.saveFailed ||
        _writer != null ||
        _pending == null) {
      return false;
    }
    _writeHalted = false;
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      LocalStructuredState(
        phase: LocalStructuredPhase.editing,
        body: _state.body,
        metadata: _state.metadata,
        remoteStatus: _state.remoteStatus,
        baseComparison: _state.baseComparison,
        recoveryAvailable: _recovery != null,
        saving: true,
        hasUnsavedChanges: true,
      ),
    );
    return true;
  }

  Future<LocalStructuredFlushResult> flush() async {
    if (!_checkIdentity()) {
      return _state.phase == LocalStructuredPhase.closed
          ? LocalStructuredFlushResult.closed
          : LocalStructuredFlushResult.obsolete;
    }
    while (_writer != null) {
      await _writer;
    }
    if (!_checkIdentity()) return LocalStructuredFlushResult.obsolete;
    return switch (_state.phase) {
      LocalStructuredPhase.saveFailed => LocalStructuredFlushResult.failed,
      LocalStructuredPhase.conflict => LocalStructuredFlushResult.conflict,
      LocalStructuredPhase.editing => LocalStructuredFlushResult.saved,
      _ => LocalStructuredFlushResult.notReady,
    };
  }

  /// No implicit discard. Refuse to close on an active failed/conflicting save
  /// so the caller can preserve the current in-memory edit or retry. When the
  /// identity has already changed, close still waits for accepted writes.
  /// [abandonUnsaved] is an explicit acknowledgement that a failed/conflicting
  /// in-memory edit will be lost. It never deletes the stored recovery row.
  Future<bool> close({bool abandonUnsaved = false}) async {
    if (_state.phase == LocalStructuredPhase.closed) return true;
    if (_closing || _discarding) return false;
    _closing = true;
    _openGeneration++;
    while (_writer != null) {
      await _writer;
    }
    if (_pending != null && !abandonUnsaved) {
      _closing = false;
      return false;
    }
    await _identitySubscription.cancel();
    _remote = null;
    _recovery = null;
    _base = null;
    _baseMetadata = null;
    _pending = null;
    _set(const LocalStructuredState(phase: LocalStructuredPhase.closed));
    await _changes.close();
    return true;
  }
}

StructuredBaseComparison _compareBase(
  StructuredBodyRecovery local,
  StructuredEditionReadResult? read,
) {
  final remote = read?.edition;
  if (remote == null) return StructuredBaseComparison.remoteUnavailable;
  if (local.base.version != remote.body.version ||
      jsonEncode(local.base.blocks) != jsonEncode(remote.body.blocks)) {
    return StructuredBaseComparison.bodyDiffers;
  }
  final baseMetadata = local.baseMetadata;
  final metadata = remote.metadata;
  if (baseMetadata == null ||
      remote.metadataIssues.isNotEmpty ||
      [
        baseMetadata.slug,
        baseMetadata.title,
        baseMetadata.summary,
        baseMetadata.workType,
        baseMetadata.publicationState,
        baseMetadata.tags,
        baseMetadata.categories,
        baseMetadata.cover,
        metadata.slug,
        metadata.title,
        metadata.summary,
        metadata.workType,
        metadata.publicationState,
        metadata.tags,
        metadata.categories,
        metadata.cover,
      ].any((value) => value == null)) {
    return StructuredBaseComparison.metadataUnknown;
  }
  if (jsonEncode(local.baseMetadata!.toJson()) !=
      jsonEncode(remote.metadata.toJson())) {
    return StructuredBaseComparison.metadataDiffers;
  }
  return StructuredBaseComparison.representedFieldsMatch;
}

bool _sameKey(StructuredBodyKey a, StructuredBodyKey b) =>
    a.userId == b.userId && a.articleId == b.articleId && a.locale == b.locale;
