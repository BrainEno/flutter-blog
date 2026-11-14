import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';

enum LocalTextPhase {
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

enum LocalTextFlushResult {
  saved,
  failed,
  conflict,
  notReady,
  obsolete,
  closed,
}

enum LocalTextFinishResult {
  finished,
  invalid,
  failed,
  conflict,
  notReady,
  obsolete,
}

/// Local snapshots only. An intermediate value is never a server body. Values
/// already delivered to a consumer cannot be revoked on identity changes.
class LocalTextState {
  const LocalTextState({
    required this.phase,
    this.body,
    this.text,
    this.bufferAvailable = false,
    this.saving = false,
    this.hasUnsavedChanges = false,
    this.finishing = false,
  });

  final LocalTextPhase phase;
  final StructuredArticleDraft? body;
  final String? text;
  final bool bufferAvailable;
  final bool saving;
  final bool hasUnsavedChanges;
  final bool finishing;
}

/// Coordinates one plain-text target in an existing, explicitly selected local
/// recovery. It does not contact the server, create a parent recovery, publish,
/// or adopt a snapshot into another editing session. On completion, consumers
/// must reopen the recovery using its new CAS revision before editing the body.
///
/// This is intentionally not connected to UI. Only unformatted text targets
/// are supported. Recovery is always a decision even without a saved buffer.
/// The selected row id protects against deletion and recreation while opening.
/// Writes accepted before identity change finish only under the captured key;
/// visible state is immediately cleared and no new writes are accepted.
class LocalStructuredTextSession {
  LocalStructuredTextSession({
    required this.key,
    required this.selectedRowId,
    required this.blockId,
    required this.fence,
    required this.identity,
    required this.store,
    this.expectedUnbufferedParent,
    this.expectedBufferedRecovery,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (selectedRowId <= 0 ||
        (expectedUnbufferedParent != null &&
            expectedBufferedRecovery != null)) {
      throw ArgumentError('Invalid selected recovery');
    }
    _subscription = identity.identityChanges.listen((_) => _checkIdentity());
  }

  final StructuredBodyKey key;
  final int selectedRowId;
  final String blockId;
  final NowaveSessionFence fence;
  final NowaveSessionIdentity identity;
  final StructuredTextSessionStore store;

  /// When handed off from a body editor, require the precise unbuffered
  /// snapshot that editor closed with, not merely the same row incarnation.
  /// Ordinary recovery opens may omit this and still require explicit consent.
  final StructuredBodyRecovery? expectedUnbufferedParent;

  /// For an explicitly selected indexed buffer, require the same exact raw
  /// buffer and parent snapshot at open. Null is not an absent-buffer claim.
  final StructuredTextBufferRecovery? expectedBufferedRecovery;
  final DateTime Function() _now;
  final _changes = StreamController<LocalTextState>.broadcast(sync: true);
  late final StreamSubscription<void> _subscription;
  LocalTextState _state = const LocalTextState(phase: LocalTextPhase.initial);
  StructuredBodyRecovery? _parent;
  StructuredTextBufferRecovery? _saved;
  StructuredTextBuffer? _pending;
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

  Stream<LocalTextState> get changes => _changes.stream;
  LocalTextState get state {
    _checkIdentity();
    return _state;
  }

  bool get _matches =>
      key.userId == fence.userId &&
      identity.activeUserId == fence.userId &&
      identity.sessionGeneration == fence.generation &&
      !(identity.accessToken?.isEmpty ?? true);

  bool _checkIdentity() {
    if (!_invalidated && !_matches && _state.phase != LocalTextPhase.closed) {
      _invalidated = true;
      _generation++;
      _set(const LocalTextState(phase: LocalTextPhase.invalidated));
    }
    return !_invalidated && _matches && _state.phase != LocalTextPhase.closed;
  }

  void _set(LocalTextState next) {
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

  /// Read the exact selected recovery. A buffer is checked first; the ordinary
  /// read fails closed if a buffer appears between the two reads. No remote
  /// result is used as a fallback if local data is missing or damaged.
  Future<void> open() async {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalTextPhase.initial) {
      return;
    }
    final done = Completer<void>();
    _opening = done;
    final generation = ++_generation;
    try {
      _set(const LocalTextState(phase: LocalTextPhase.opening));
      if (_closing || !_checkIdentity() || generation != _generation) return;
      final saved = await store.loadTextBuffer(key);
      if (_closing || !_checkIdentity() || generation != _generation) return;
      final parent = saved?.parent ?? await store.load(key);
      if (_closing || !_checkIdentity() || generation != _generation) return;
      if (parent == null ||
          parent.rowId != selectedRowId ||
          !_sameKey(parent.key, key)) {
        _set(const LocalTextState(phase: LocalTextPhase.conflict));
        return;
      }
      final expected = expectedUnbufferedParent;
      if (expected != null &&
          (saved != null || !_sameSnapshot(parent, expected))) {
        _set(const LocalTextState(phase: LocalTextPhase.conflict));
        return;
      }
      final expectedBuffer = expectedBufferedRecovery;
      if (expectedBuffer != null &&
          (saved == null ||
              !_sameSnapshot(saved.parent, expectedBuffer.parent) ||
              saved.storageJson != expectedBuffer.storageJson)) {
        _set(const LocalTextState(phase: LocalTextPhase.conflict));
        return;
      }
      if (saved != null && saved.buffer.blockId != blockId) {
        _set(
          const LocalTextState(
            phase: LocalTextPhase.conflict,
            bufferAvailable: true,
          ),
        );
        return;
      }
      final target = StructuredTextBuffer(blockId: blockId, text: '');
      target.validateTarget(parent.body);
      final text =
          saved?.buffer.text ??
          parent.body.blocks.singleWhere(
                (block) => block['id'] == blockId,
              )['text']
              as String;
      _parent = parent;
      _saved = saved;
      _set(
        LocalTextState(
          phase: LocalTextPhase.recoveryChoice,
          body: parent.body,
          text: text,
          bufferAvailable: saved != null,
        ),
      );
    } on Object {
      if (!_closing && _checkIdentity() && generation == _generation) {
        _set(const LocalTextState(phase: LocalTextPhase.loadFailed));
      }
    } finally {
      _opening = null;
      done.complete();
    }
  }

  /// Explicitly resume the displayed local recovery; no write occurs here.
  bool resume() {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalTextPhase.recoveryChoice) {
      return false;
    }
    _set(
      LocalTextState(
        phase: LocalTextPhase.editing,
        body: _state.body,
        text: _state.text,
        bufferAvailable: _saved != null,
      ),
    );
    return true;
  }

  /// Cancel the choice without changing the database.
  bool cancel() {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalTextPhase.recoveryChoice) {
      return false;
    }
    _parent = null;
    _saved = null;
    _set(const LocalTextState(phase: LocalTextPhase.cancelled));
    return true;
  }

  bool get _canEdit =>
      _checkIdentity() &&
      !_closing &&
      !_finishing &&
      (_state.phase == LocalTextPhase.editing ||
          _state.phase == LocalTextPhase.actionFailed);

  /// Accept input synchronously, including temporarily invalid body text. A
  /// too-large value throws before changing state or scheduling a write.
  bool edit(String text) {
    if (!_canEdit) return false;
    final buffer = StructuredTextBuffer(blockId: blockId, text: text);
    buffer.validateTarget(_parent!.body);
    _pending = buffer;
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      LocalTextState(
        phase: LocalTextPhase.editing,
        body: _parent!.body,
        text: text,
        bufferAvailable: _saved != null,
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
    while (_pending != null) {
      final edit = _pending!;
      _pending = null;
      try {
        final previous = _saved;
        final saved = previous == null
            ? await store.createTextBuffer(
                expected: _parent!,
                buffer: edit,
                updatedAt: _now().toUtc(),
              )
            : await store.replaceTextBuffer(
                expected: previous,
                buffer: edit,
                updatedAt: _now().toUtc(),
              );
        if (saved == null) {
          _pending ??= edit;
          _halted = true;
          _failure(LocalTextPhase.conflict);
          return;
        }
        _saved = saved;
        _parent = saved.parent;
        _uncertainFinish = false;
      } on Object {
        _pending ??= edit;
        _halted = true;
        _failure(LocalTextPhase.saveFailed);
        return;
      }
    }
    if (_checkIdentity()) {
      _set(
        LocalTextState(
          phase: LocalTextPhase.editing,
          body: _parent!.body,
          text: _state.text,
          bufferAvailable: _saved != null,
          finishing: _finishing,
        ),
      );
    }
  }

  void _failure(LocalTextPhase phase) {
    if (!_checkIdentity()) return;
    _set(
      LocalTextState(
        phase: phase,
        body: _parent?.body,
        text: _state.text,
        bufferAvailable: _saved != null,
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
        _state.phase != LocalTextPhase.saveFailed ||
        _writer != null ||
        _pending == null) {
      return false;
    }
    _halted = false;
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      LocalTextState(
        phase: LocalTextPhase.editing,
        body: _parent!.body,
        text: _state.text,
        bufferAvailable: _saved != null,
        saving: true,
        hasUnsavedChanges: true,
      ),
    );
    return true;
  }

  Future<LocalTextFlushResult> flush() async {
    if (!_checkIdentity()) {
      return _state.phase == LocalTextPhase.closed
          ? LocalTextFlushResult.closed
          : LocalTextFlushResult.obsolete;
    }
    while (_writer != null) {
      await _writer;
    }
    if (!_checkIdentity()) return LocalTextFlushResult.obsolete;
    return switch (_state.phase) {
      LocalTextPhase.editing => LocalTextFlushResult.saved,
      LocalTextPhase.saveFailed ||
      LocalTextPhase.actionFailed => LocalTextFlushResult.failed,
      LocalTextPhase.conflict => LocalTextFlushResult.conflict,
      _ => LocalTextFlushResult.notReady,
    };
  }

  /// Apply only after explicit confirmation. Invalid intermediate text remains
  /// saved as a buffer, and no validated body or publishing payload is made.
  Future<LocalTextFinishResult> apply({required bool confirmed}) =>
      _finish(confirmed: confirmed, apply: true);

  /// Discard only the buffer, never the parent recovery. If there is no buffer,
  /// finish without writing anything. A newer row is never deleted.
  Future<LocalTextFinishResult> discard({required bool confirmed}) =>
      _finish(confirmed: confirmed, apply: false);

  Future<LocalTextFinishResult> _finish({
    required bool confirmed,
    required bool apply,
  }) async {
    if (!confirmed || !_canEdit) return LocalTextFinishResult.notReady;
    _finishing = true;
    final done = Completer<void>();
    _finishingDone = done;
    try {
      _set(
        LocalTextState(
          phase: _state.phase,
          body: _state.body,
          text: _state.text,
          bufferAvailable: _saved != null,
          saving: _writer != null,
          hasUnsavedChanges:
              _pending != null || _writer != null || _uncertainFinish,
          finishing: true,
        ),
      );
      if (_closing || !_checkIdentity()) return LocalTextFinishResult.obsolete;
      final flushed = await flush();
      if (_closing || !_checkIdentity()) return LocalTextFinishResult.obsolete;
      if (flushed == LocalTextFlushResult.conflict) {
        return LocalTextFinishResult.conflict;
      }
      // An earlier finish may have committed before reporting an error. A
      // deliberate action retry is safe only with its original CAS token;
      // flush must not claim that this uncertain outcome was saved.
      final retryingAction =
          _state.phase == LocalTextPhase.actionFailed &&
          _uncertainFinish &&
          _pending == null &&
          _writer == null;
      if (flushed != LocalTextFlushResult.saved && !retryingAction) {
        return LocalTextFinishResult.failed;
      }
      final saved = _saved;
      if (saved == null) {
        _set(
          LocalTextState(phase: LocalTextPhase.finished, body: _parent!.body),
        );
        return LocalTextFinishResult.finished;
      }
      if (apply) {
        try {
          saved.buffer.applyTo(saved.parent.body);
        } on FormatException {
          return LocalTextFinishResult.invalid;
        }
      }
      final result = apply
          ? await store.applyTextBuffer(
              expected: saved,
              updatedAt: _now().toUtc(),
            )
          : await store.discardTextBuffer(
              expected: saved,
              updatedAt: _now().toUtc(),
            );
      if (result == null) _uncertainFinish = true;
      if (!_checkIdentity()) return LocalTextFinishResult.obsolete;
      if (result == null) {
        _failure(LocalTextPhase.conflict);
        return LocalTextFinishResult.conflict;
      }
      _uncertainFinish = false;
      _parent = result;
      _saved = null;
      _set(LocalTextState(phase: LocalTextPhase.finished, body: result.body));
      return LocalTextFinishResult.finished;
    } on Object {
      _uncertainFinish = true;
      if (_checkIdentity()) _failure(LocalTextPhase.actionFailed);
      return _invalidated
          ? LocalTextFinishResult.obsolete
          : LocalTextFinishResult.failed;
    } finally {
      _finishing = false;
      _finishingDone = null;
      if (_checkIdentity() && _state.finishing) {
        _set(
          LocalTextState(
            phase: _state.phase,
            body: _state.body,
            text: _state.text,
            bufferAvailable: _state.bufferAvailable,
            saving: _state.saving,
            hasUnsavedChanges: _state.hasUnsavedChanges,
          ),
        );
      }
      done.complete();
    }
  }

  /// Wait for admitted reads, writes and finish actions. A failed/conflicting
  /// unsaved edit requires explicit acknowledgement before closing. Closing
  /// never deletes the persisted recovery or buffer.
  Future<bool> close({bool abandonUnsaved = false}) async {
    if (_state.phase == LocalTextPhase.closed) return true;
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
    _set(const LocalTextState(phase: LocalTextPhase.closed));
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
