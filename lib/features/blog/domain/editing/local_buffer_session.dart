import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';

/// The phases shared by every single-target local buffer session (#291).
///
/// `LocalTextPhase` and `LocalRichTextPhase` are aliases of this enum: the two
/// sessions always had the same state machine, now they have one copy of it.
enum LocalBufferPhase {
  initial,
  opening,
  recoveryChoice,
  editing,
  loadFailed,
  saveFailed,
  actionFailed,
  conflict,
  finished,
  cancelled,
  invalidated,
  closed,
}

/// The outcome of waiting for admitted writes; see [LocalBufferSession.flush].
enum LocalBufferFlushResult {
  saved,
  failed,
  conflict,
  notReady,
  obsolete,
  closed,
}

/// The outcome of an explicit apply or discard; see [LocalBufferSession.apply].
enum LocalBufferFinishResult {
  finished,
  invalid,
  failed,
  conflict,
  notReady,
  obsolete,
}

/// Local snapshots only. An intermediate value is never a server body. Values
/// already delivered to a consumer cannot be revoked on identity changes.
///
/// [V] is what the editor edits: the plain text of one block, or an immutable
/// rich-text buffer. Subclasses give [value] its domain name.
abstract class LocalBufferState<V> {
  const LocalBufferState({
    required this.phase,
    this.body,
    this.bufferAvailable = false,
    this.saving = false,
    this.hasUnsavedChanges = false,
    this.finishing = false,
  });

  final LocalBufferPhase phase;
  final StructuredArticleDraft? body;
  final bool bufferAvailable;
  final bool saving;
  final bool hasUnsavedChanges;
  final bool finishing;

  /// The value shown to the editor, when the phase carries one.
  V? get value;
}

/// The type-specific half of a buffer session: the store calls for one buffer
/// kind, how a buffer is validated against its target, and how a state is
/// built. Each session keeps its port private, so none of these operations is
/// reachable from a caller - the state machine is the only way in.
///
/// [V] is the edited value, [B] the persisted buffer, [R] the buffered
/// recovery row (parent snapshot + buffer + raw JSON token) and [S] the state.
abstract interface class LocalBufferPort<
  V,
  B,
  R,
  S extends LocalBufferState<V>
> {
  Future<R?> loadBuffer(StructuredBodyKey key);

  Future<R?> createBuffer({
    required StructuredBodyRecovery expected,
    required B buffer,
    required DateTime updatedAt,
  });

  Future<R?> replaceBuffer({
    required R expected,
    required B buffer,
    required DateTime updatedAt,
  });

  Future<StructuredBodyRecovery?> applyBuffer({
    required R expected,
    required DateTime updatedAt,
  });

  Future<StructuredBodyRecovery?> discardBuffer({
    required R expected,
    required DateTime updatedAt,
  });

  StructuredBodyRecovery parentOf(R recovery);

  B bufferOf(R recovery);

  /// The raw persisted JSON, compared exactly when a buffer was preselected.
  String storageJsonOf(R recovery);

  /// Whether a persisted [buffer] addresses this session's target.
  bool targetsThis(B buffer);

  /// The value to offer at the recovery choice. Validates the target against
  /// [parent] and throws when it no longer exists or has the wrong shape.
  V initialValue(StructuredBodyRecovery parent, R? saved);

  /// The buffer to persist for an edited [value]. Throws, before any state
  /// change, when the value addresses another target or is out of bounds.
  B bufferForEdit(V value, StructuredArticleDraft body);

  /// Throws [FormatException] when [buffer] cannot be applied to [body].
  void checkApplicable(B buffer, StructuredArticleDraft body);

  S state({
    required LocalBufferPhase phase,
    StructuredArticleDraft? body,
    V? value,
    bool bufferAvailable,
    bool saving,
    bool hasUnsavedChanges,
    bool finishing,
  });
}

/// Coordinates one explicitly selected target in one existing local
/// recovery (#291: the shared engine of the plain-text and rich-text
/// sessions).
///
/// It never contacts the server, creates a parent recovery, publishes, or
/// adopts a snapshot into another editing session. The selected row id
/// protects against deletion and recreation while opening. Writes accepted
/// before an identity change finish only under the captured key; visible state
/// is cleared at once and no new writes are accepted. Consumers must reopen
/// the recovery with its new CAS revision after finishing.
///
/// What differs between the two sessions is deliberately small and explicit:
/// the [LocalBufferPort], whether a preselected token is mandatory, and
/// whether finishing without a buffer re-reads the parent first.
class LocalBufferSession<V, B, R, S extends LocalBufferState<V>> {
  LocalBufferSession({
    required this.key,
    required this.selectedRowId,
    required this.fence,
    required this.identity,
    required StructuredBodyRecoveryStore recoveries,
    required LocalBufferPort<V, B, R, S> port,
    required bool requireExpectedToken,
    required bool verifyParentBeforeEmptyFinish,
    StructuredBodyRecovery? expectedUnbufferedParent,
    R? expectedBufferedRecovery,
    DateTime Function()? now,
  }) : _recoveries = recoveries,
       _port = port,
       _verifyParentBeforeEmptyFinish = verifyParentBeforeEmptyFinish,
       _expectedUnbufferedParent = expectedUnbufferedParent,
       _expectedBufferedRecovery = expectedBufferedRecovery,
       _now = now ?? DateTime.now,
       _state = port.state(phase: LocalBufferPhase.initial) {
    final both =
        expectedUnbufferedParent != null && expectedBufferedRecovery != null;
    final neither =
        expectedUnbufferedParent == null && expectedBufferedRecovery == null;
    if (selectedRowId <= 0 || both || (requireExpectedToken && neither)) {
      throw ArgumentError('Invalid selected recovery');
    }
    _subscription = identity.identityChanges.listen((_) => _checkIdentity());
  }

  final StructuredBodyKey key;
  final int selectedRowId;
  final NowaveSessionFence fence;
  final NowaveSessionIdentity identity;

  final StructuredBodyRecoveryStore _recoveries;
  final LocalBufferPort<V, B, R, S> _port;
  final bool _verifyParentBeforeEmptyFinish;

  /// Preselected tokens are only needed by [open]. They are released after it
  /// (and on invalidation or close) so a session never pins an old snapshot.
  StructuredBodyRecovery? _expectedUnbufferedParent;
  R? _expectedBufferedRecovery;

  final DateTime Function() _now;
  final StreamController<S> _changes = StreamController<S>.broadcast(
    sync: true,
  );
  late final StreamSubscription<void> _subscription;
  S _state;
  StructuredBodyRecovery? _parent;
  R? _saved;
  B? _pending;
  Future<void>? _writer;
  Completer<void>? _opening;
  Completer<void>? _finishingDone;
  bool _finishing = false;
  bool _closing = false;
  bool _invalidated = false;
  bool _halted = false;
  bool _uncertainFinish = false;
  bool _notifying = false;
  bool _notificationPending = false;
  int _generation = 0;

  Stream<S> get changes => _changes.stream;

  S get state {
    _checkIdentity();
    return _state;
  }

  bool get _matches =>
      key.userId == fence.userId &&
      identity.activeUserId == fence.userId &&
      identity.sessionGeneration == fence.generation &&
      !(identity.accessToken?.isEmpty ?? true);

  bool _checkIdentity() {
    if (!_invalidated && !_matches && _state.phase != LocalBufferPhase.closed) {
      _invalidated = true;
      _generation++;
      _releaseExpectedTokens();
      _set(_port.state(phase: LocalBufferPhase.invalidated));
    }
    return !_invalidated && _matches && _state.phase != LocalBufferPhase.closed;
  }

  void _releaseExpectedTokens() {
    _expectedUnbufferedParent = null;
    _expectedBufferedRecovery = null;
  }

  void _set(S next) {
    _state = next;
    if (_changes.isClosed) return;
    if (_notifying) {
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

  /// A state that keeps the current phase, body and value, with fresh flags.
  S _with({
    required LocalBufferPhase phase,
    StructuredArticleDraft? body,
    V? value,
    bool saving = false,
    bool hasUnsavedChanges = false,
    bool finishing = false,
  }) => _port.state(
    phase: phase,
    body: body,
    value: value,
    bufferAvailable: _saved != null,
    saving: saving,
    hasUnsavedChanges: hasUnsavedChanges,
    finishing: finishing,
  );

  /// Read the exact selected recovery. A buffer is checked first; the ordinary
  /// read fails closed if a buffer appears between the two reads. No remote
  /// result is used as a fallback if local data is missing or damaged.
  Future<void> open() async {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalBufferPhase.initial) {
      return;
    }
    final done = Completer<void>();
    _opening = done;
    final generation = ++_generation;
    try {
      _set(_port.state(phase: LocalBufferPhase.opening));
      if (_closing || !_checkIdentity() || generation != _generation) return;
      final saved = await _port.loadBuffer(key);
      if (_closing || !_checkIdentity() || generation != _generation) return;
      final parent = saved != null
          ? _port.parentOf(saved)
          : await _recoveries.load(key);
      if (_closing || !_checkIdentity() || generation != _generation) return;
      if (parent == null ||
          parent.rowId != selectedRowId ||
          !_sameKey(parent.key, key)) {
        _set(_port.state(phase: LocalBufferPhase.conflict));
        return;
      }
      final expected = _expectedUnbufferedParent;
      if (expected != null &&
          (saved != null || !_sameSnapshot(parent, expected))) {
        _set(_port.state(phase: LocalBufferPhase.conflict));
        return;
      }
      final expectedBuffer = _expectedBufferedRecovery;
      if (expectedBuffer != null &&
          (saved == null ||
              !_sameSnapshot(
                _port.parentOf(saved),
                _port.parentOf(expectedBuffer),
              ) ||
              _port.storageJsonOf(saved) !=
                  _port.storageJsonOf(expectedBuffer))) {
        _set(_port.state(phase: LocalBufferPhase.conflict));
        return;
      }
      if (saved != null && !_port.targetsThis(_port.bufferOf(saved))) {
        _set(
          _port.state(phase: LocalBufferPhase.conflict, bufferAvailable: true),
        );
        return;
      }
      final value = _port.initialValue(parent, saved);
      _parent = parent;
      _saved = saved;
      _set(
        _with(
          phase: LocalBufferPhase.recoveryChoice,
          body: parent.body,
          value: value,
        ),
      );
    } on Object {
      if (!_closing && _checkIdentity() && generation == _generation) {
        _set(_port.state(phase: LocalBufferPhase.loadFailed));
      }
    } finally {
      _releaseExpectedTokens();
      _opening = null;
      done.complete();
    }
  }

  /// Explicitly resume the displayed local recovery; no write occurs here.
  bool resume() {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalBufferPhase.recoveryChoice) {
      return false;
    }
    _set(
      _with(
        phase: LocalBufferPhase.editing,
        body: _state.body,
        value: _state.value,
      ),
    );
    return true;
  }

  /// Cancel the choice without changing the database.
  bool cancel() {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalBufferPhase.recoveryChoice) {
      return false;
    }
    _parent = null;
    _saved = null;
    _set(_port.state(phase: LocalBufferPhase.cancelled));
    return true;
  }

  bool get _canEdit =>
      _checkIdentity() &&
      !_closing &&
      !_finishing &&
      (_state.phase == LocalBufferPhase.editing ||
          _state.phase == LocalBufferPhase.actionFailed ||
          _state.phase == LocalBufferPhase.saveFailed ||
          _state.phase == LocalBufferPhase.conflict);

  /// Accept input synchronously, including temporarily invalid body text. A
  /// value for another target, or one out of bounds, throws before changing
  /// state or scheduling a write.
  bool edit(V value) {
    if (!_canEdit) return false;
    final buffer = _port.bufferForEdit(value, _parent!.body);
    _pending = buffer;
    if (_state.phase == LocalBufferPhase.saveFailed ||
        _state.phase == LocalBufferPhase.conflict) {
      // Preserve late IME input in memory. Neither a failure nor a conflict
      // may trigger an implicit retry or overwrite a newer local recovery.
      _set(
        _with(
          phase: _state.phase,
          body: _parent!.body,
          value: value,
          hasUnsavedChanges: true,
        ),
      );
      return true;
    }
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      _with(
        phase: LocalBufferPhase.editing,
        body: _parent!.body,
        value: value,
        saving: true,
        hasUnsavedChanges: true,
      ),
    );
    return true;
  }

  void _startWriter() {
    if (_writer != null || _pending == null || _halted) return;
    final done = Completer<void>();
    _writer = done.future;
    unawaited(
      _drain().whenComplete(() {
        _writer = null;
        if (_pending != null && !_halted) _startWriter();
        done.complete();
      }),
    );
  }

  Future<void> _drain() async {
    for (var edit = _pending; edit != null; edit = _pending) {
      _pending = null;
      try {
        final previous = _saved;
        final saved = previous == null
            ? await _port.createBuffer(
                expected: _parent!,
                buffer: edit,
                updatedAt: _now().toUtc(),
              )
            : await _port.replaceBuffer(
                expected: previous,
                buffer: edit,
                updatedAt: _now().toUtc(),
              );
        if (saved == null) {
          _pending ??= edit;
          _halted = true;
          _failure(LocalBufferPhase.conflict);
          return;
        }
        _saved = saved;
        _parent = _port.parentOf(saved);
        _uncertainFinish = false;
      } on Object {
        _pending ??= edit;
        _halted = true;
        _failure(LocalBufferPhase.saveFailed);
        return;
      }
    }
    if (_checkIdentity()) {
      _set(
        _with(
          phase: LocalBufferPhase.editing,
          body: _parent!.body,
          value: _state.value,
          finishing: _finishing,
        ),
      );
    }
  }

  void _failure(LocalBufferPhase phase) {
    if (!_checkIdentity()) return;
    _set(
      _with(
        phase: phase,
        body: _parent?.body,
        value: _state.value,
        hasUnsavedChanges: _pending != null || _uncertainFinish,
        finishing: _finishing,
      ),
    );
  }

  /// Retry only a storage failure, never a CAS conflict. If a failure happened
  /// after commit, the old token will conflict rather than overwrite that row.
  bool retrySave() {
    if (!_checkIdentity() ||
        _closing ||
        _finishing ||
        _state.phase != LocalBufferPhase.saveFailed ||
        _writer != null ||
        _pending == null) {
      return false;
    }
    _halted = false;
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      _with(
        phase: LocalBufferPhase.editing,
        body: _parent!.body,
        value: _state.value,
        saving: true,
        hasUnsavedChanges: true,
      ),
    );
    return true;
  }

  Future<LocalBufferFlushResult> flush() async {
    if (!_checkIdentity()) {
      return _state.phase == LocalBufferPhase.closed
          ? LocalBufferFlushResult.closed
          : LocalBufferFlushResult.obsolete;
    }
    while (_writer != null) {
      await _writer;
    }
    if (!_checkIdentity()) return LocalBufferFlushResult.obsolete;
    return switch (_state.phase) {
      LocalBufferPhase.editing => LocalBufferFlushResult.saved,
      LocalBufferPhase.saveFailed ||
      LocalBufferPhase.actionFailed => LocalBufferFlushResult.failed,
      LocalBufferPhase.conflict => LocalBufferFlushResult.conflict,
      _ => LocalBufferFlushResult.notReady,
    };
  }

  /// Apply only after explicit confirmation. Invalid intermediate text remains
  /// saved as a buffer, and no validated body or publishing payload is made.
  Future<LocalBufferFinishResult> apply({required bool confirmed}) =>
      _finish(confirmed: confirmed, apply: true);

  /// Discard only the buffer, never the parent recovery. If there is no buffer,
  /// finish without writing anything. A newer row is never deleted.
  Future<LocalBufferFinishResult> discard({required bool confirmed}) =>
      _finish(confirmed: confirmed, apply: false);

  Future<LocalBufferFinishResult> _finish({
    required bool confirmed,
    required bool apply,
  }) async {
    if (!confirmed ||
        !_canEdit ||
        _state.phase == LocalBufferPhase.saveFailed ||
        _state.phase == LocalBufferPhase.conflict) {
      return LocalBufferFinishResult.notReady;
    }
    _finishing = true;
    final done = Completer<void>();
    _finishingDone = done;
    try {
      _set(
        _with(
          phase: _state.phase,
          body: _state.body,
          value: _state.value,
          saving: _writer != null,
          hasUnsavedChanges:
              _pending != null || _writer != null || _uncertainFinish,
          finishing: true,
        ),
      );
      if (_closing || !_checkIdentity()) {
        return LocalBufferFinishResult.obsolete;
      }
      final flushed = await flush();
      if (_closing || !_checkIdentity()) {
        return LocalBufferFinishResult.obsolete;
      }
      if (flushed == LocalBufferFlushResult.conflict) {
        return LocalBufferFinishResult.conflict;
      }
      // An earlier finish may have committed before reporting an error. A
      // deliberate action retry is safe only with its original CAS token;
      // flush must not claim that this uncertain outcome was saved.
      final retryingAction =
          _state.phase == LocalBufferPhase.actionFailed &&
          _uncertainFinish &&
          _pending == null &&
          _writer == null;
      if (flushed != LocalBufferFlushResult.saved && !retryingAction) {
        return LocalBufferFinishResult.failed;
      }
      final saved = _saved;
      if (saved == null) {
        return await _finishWithoutBuffer();
      }
      if (apply) {
        try {
          _port.checkApplicable(
            _port.bufferOf(saved),
            _port.parentOf(saved).body,
          );
        } on FormatException {
          return LocalBufferFinishResult.invalid;
        }
      }
      final result = apply
          ? await _port.applyBuffer(expected: saved, updatedAt: _now().toUtc())
          : await _port.discardBuffer(
              expected: saved,
              updatedAt: _now().toUtc(),
            );
      if (result == null) _uncertainFinish = true;
      if (!_checkIdentity()) return LocalBufferFinishResult.obsolete;
      if (result == null) {
        _failure(LocalBufferPhase.conflict);
        return LocalBufferFinishResult.conflict;
      }
      _uncertainFinish = false;
      _parent = result;
      _saved = null;
      _set(_port.state(phase: LocalBufferPhase.finished, body: result.body));
      return LocalBufferFinishResult.finished;
    } on Object {
      _uncertainFinish = true;
      if (_checkIdentity()) _failure(LocalBufferPhase.actionFailed);
      return _invalidated
          ? LocalBufferFinishResult.obsolete
          : LocalBufferFinishResult.failed;
    } finally {
      _finishing = false;
      _finishingDone = null;
      if (_checkIdentity() && _state.finishing) {
        _set(
          _port.state(
            phase: _state.phase,
            body: _state.body,
            value: _state.value,
            bufferAvailable: _state.bufferAvailable,
            saving: _state.saving,
            hasUnsavedChanges: _state.hasUnsavedChanges,
          ),
        );
      }
      done.complete();
    }
  }

  /// Nothing was ever buffered: finishing writes nothing. When the session
  /// asks for it, the parent is re-read first, so a body changed elsewhere in
  /// the meantime is reported as a conflict instead of a stale success.
  Future<LocalBufferFinishResult> _finishWithoutBuffer() async {
    if (!_verifyParentBeforeEmptyFinish) {
      _set(_port.state(phase: LocalBufferPhase.finished, body: _parent!.body));
      return LocalBufferFinishResult.finished;
    }
    final parent = await _recoveries.load(key);
    if (_closing || !_checkIdentity()) {
      return LocalBufferFinishResult.obsolete;
    }
    if (parent == null || !_sameSnapshot(parent, _parent!)) {
      _uncertainFinish = true;
      _failure(LocalBufferPhase.conflict);
      return LocalBufferFinishResult.conflict;
    }
    _set(_port.state(phase: LocalBufferPhase.finished, body: parent.body));
    return LocalBufferFinishResult.finished;
  }

  /// Wait for admitted reads, writes and finish actions. A failed/conflicting
  /// unsaved edit requires explicit acknowledgement before closing. Closing
  /// never deletes the persisted recovery or buffer.
  Future<bool> close({bool abandonUnsaved = false}) async {
    if (_state.phase == LocalBufferPhase.closed) return true;
    if (_closing) return false;
    _closing = true;
    _generation++;
    final opening = _opening;
    if (opening != null) await opening.future;
    final finishing = _finishingDone;
    if (finishing != null) await finishing.future;
    while (_writer != null) {
      await _writer;
    }
    if ((_pending != null || _uncertainFinish) && !abandonUnsaved) {
      _closing = false;
      return false;
    }
    await _subscription.cancel();
    _parent = null;
    _saved = null;
    _pending = null;
    _releaseExpectedTokens();
    _set(_port.state(phase: LocalBufferPhase.closed));
    await _changes.close();
    return true;
  }
}

bool _sameKey(StructuredBodyKey a, StructuredBodyKey b) =>
    a.userId == b.userId && a.articleId == b.articleId && a.locale == b.locale;

// Compare the same local token fields used by the SQLite body CAS. Equality
// is deliberately exact, including raw JSON and nullable metadata.
bool _sameSnapshot(StructuredBodyRecovery a, StructuredBodyRecovery b) =>
    _sameKey(a.key, b.key) &&
    a.backendStorageKey == b.backendStorageKey &&
    a.rowId == b.rowId &&
    a.revision == b.revision &&
    a.base.version == b.base.version &&
    a.baseStorageJson == b.baseStorageJson &&
    a.body.version == b.body.version &&
    a.bodyStorageJson == b.bodyStorageJson &&
    a.updatedAt.microsecondsSinceEpoch == b.updatedAt.microsecondsSinceEpoch &&
    a.baseMetadataStorageJson == b.baseMetadataStorageJson &&
    a.sessionMetadataStorageJson == b.sessionMetadataStorageJson;
