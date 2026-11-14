import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_session_store.dart';

enum LocalRichTextPhase {
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

enum LocalRichTextFlushResult {
  saved,
  failed,
  conflict,
  notReady,
  obsolete,
  closed,
}

enum LocalRichTextFinishResult {
  finished,
  invalid,
  failed,
  conflict,
  notReady,
  obsolete,
}

/// Local snapshots only. An intermediate value is never a server body. Values
/// already delivered to a consumer cannot be revoked on identity changes.
class LocalRichTextState {
  const LocalRichTextState({
    required this.phase,
    this.body,
    this.buffer,
    this.bufferAvailable = false,
    this.saving = false,
    this.hasUnsavedChanges = false,
    this.finishing = false,
  });

  final LocalRichTextPhase phase;
  final StructuredArticleDraft? body;
  final StructuredRichTextBuffer? buffer;
  final bool bufferAvailable;
  final bool saving;
  final bool hasUnsavedChanges;
  final bool finishing;
}

/// Coordinates a single explicitly selected formatted target in one existing
/// local recovery. Exact preselected parent or buffered tokens are mandatory;
/// list indices are never reopened using only a row ID. No network or UI is
/// involved. Consumers must reopen the row after finish and fence their route.
/// Accepted writes can finish only under their original account and backend.
/// Input not durably saved may be lost after process death or abandonment.
class LocalStructuredRichTextSession {
  LocalStructuredRichTextSession({
    required this.key,
    required this.selectedRowId,
    required this.blockId,
    required this.itemIndex,
    required this.fence,
    required this.identity,
    required this.store,
    StructuredBodyRecovery? expectedUnbufferedParent,
    StructuredRichTextBufferRecovery? expectedBufferedRecovery,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _expectedUnbufferedParent = expectedUnbufferedParent,
       _expectedBufferedRecovery = expectedBufferedRecovery {
    if (selectedRowId <= 0 ||
        (expectedUnbufferedParent == null) ==
            (expectedBufferedRecovery == null)) {
      throw ArgumentError('Invalid selected recovery');
    }
    _subscription = identity.identityChanges.listen((_) => _checkIdentity());
  }

  final StructuredBodyKey key;
  final int selectedRowId;
  final String blockId;
  final int? itemIndex;
  final NowaveSessionFence fence;
  final NowaveSessionIdentity identity;
  final StructuredRichTextSessionStore store;

  StructuredBodyRecovery? _expectedUnbufferedParent;

  StructuredRichTextBufferRecovery? _expectedBufferedRecovery;
  final DateTime Function() _now;
  final _changes = StreamController<LocalRichTextState>.broadcast(sync: true);
  late final StreamSubscription<void> _subscription;
  LocalRichTextState _state = const LocalRichTextState(
    phase: LocalRichTextPhase.initial,
  );
  StructuredBodyRecovery? _parent;
  StructuredRichTextBufferRecovery? _saved;
  StructuredRichTextBuffer? _pending;
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

  Stream<LocalRichTextState> get changes => _changes.stream;
  LocalRichTextState get state {
    _checkIdentity();
    return _state;
  }

  bool get _matches =>
      key.userId == fence.userId &&
      identity.activeUserId == fence.userId &&
      identity.sessionGeneration == fence.generation &&
      !(identity.accessToken?.isEmpty ?? true);

  bool _checkIdentity() {
    if (!_invalidated &&
        !_matches &&
        _state.phase != LocalRichTextPhase.closed) {
      _invalidated = true;
      _generation++;
      _expectedUnbufferedParent = null;
      _expectedBufferedRecovery = null;
      _set(const LocalRichTextState(phase: LocalRichTextPhase.invalidated));
    }
    return !_invalidated &&
        _matches &&
        _state.phase != LocalRichTextPhase.closed;
  }

  void _set(LocalRichTextState next) {
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
        _state.phase != LocalRichTextPhase.initial) {
      return;
    }
    final done = Completer<void>();
    _opening = done;
    final generation = ++_generation;
    try {
      _set(const LocalRichTextState(phase: LocalRichTextPhase.opening));
      if (_closing || !_checkIdentity() || generation != _generation) return;
      final saved = await store.loadRichTextBuffer(key);
      if (_closing || !_checkIdentity() || generation != _generation) return;
      final parent = saved?.parent ?? await store.load(key);
      if (_closing || !_checkIdentity() || generation != _generation) return;
      if (parent == null ||
          parent.rowId != selectedRowId ||
          !_sameKey(parent.key, key)) {
        _set(const LocalRichTextState(phase: LocalRichTextPhase.conflict));
        return;
      }
      final expected = _expectedUnbufferedParent;
      if (expected != null &&
          (saved != null || !_sameSnapshot(parent, expected))) {
        _set(const LocalRichTextState(phase: LocalRichTextPhase.conflict));
        return;
      }
      final expectedBuffer = _expectedBufferedRecovery;
      if (expectedBuffer != null &&
          (saved == null ||
              !_sameSnapshot(saved.parent, expectedBuffer.parent) ||
              saved.storageJson != expectedBuffer.storageJson)) {
        _set(const LocalRichTextState(phase: LocalRichTextPhase.conflict));
        return;
      }
      if (saved != null &&
          (saved.buffer.blockId != blockId ||
              saved.buffer.itemIndex != itemIndex)) {
        _set(
          const LocalRichTextState(
            phase: LocalRichTextPhase.conflict,
            bufferAvailable: true,
          ),
        );
        return;
      }
      final buffer =
          saved?.buffer ?? _initialBuffer(parent.body, blockId, itemIndex);
      buffer.validateTarget(parent.body);
      _parent = parent;
      _saved = saved;
      _set(
        LocalRichTextState(
          phase: LocalRichTextPhase.recoveryChoice,
          body: parent.body,
          buffer: buffer,
          bufferAvailable: saved != null,
        ),
      );
    } on Object {
      if (!_closing && _checkIdentity() && generation == _generation) {
        _set(const LocalRichTextState(phase: LocalRichTextPhase.loadFailed));
      }
    } finally {
      _expectedUnbufferedParent = null;
      _expectedBufferedRecovery = null;
      _opening = null;
      done.complete();
    }
  }

  /// Explicitly resume the displayed local recovery; no write occurs here.
  bool resume() {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalRichTextPhase.recoveryChoice) {
      return false;
    }
    _set(
      LocalRichTextState(
        phase: LocalRichTextPhase.editing,
        body: _state.body,
        buffer: _state.buffer,
        bufferAvailable: _saved != null,
      ),
    );
    return true;
  }

  /// Cancel the choice without changing the database.
  bool cancel() {
    if (!_checkIdentity() ||
        _closing ||
        _state.phase != LocalRichTextPhase.recoveryChoice) {
      return false;
    }
    _parent = null;
    _saved = null;
    _set(const LocalRichTextState(phase: LocalRichTextPhase.cancelled));
    return true;
  }

  bool get _canEdit =>
      _checkIdentity() &&
      !_closing &&
      !_finishing &&
      (_state.phase == LocalRichTextPhase.editing ||
          _state.phase == LocalRichTextPhase.actionFailed ||
          _state.phase == LocalRichTextPhase.saveFailed ||
          _state.phase == LocalRichTextPhase.conflict);

  /// Accept a bounded immutable intermediate value. Invalid final body text,
  /// selection and composing offsets may be retained without publication.
  bool edit(StructuredRichTextBuffer buffer) {
    if (!_canEdit) return false;
    if (buffer.blockId != blockId || buffer.itemIndex != itemIndex) {
      throw ArgumentError('Rich buffer target changed');
    }
    buffer.validateTarget(_parent!.body);
    _pending = buffer;
    if (_state.phase == LocalRichTextPhase.saveFailed ||
        _state.phase == LocalRichTextPhase.conflict) {
      // Preserve late IME input in memory. Neither a failure nor a conflict
      // may trigger an implicit retry or overwrite a newer local recovery.
      _set(
        LocalRichTextState(
          phase: _state.phase,
          body: _parent!.body,
          buffer: buffer,
          bufferAvailable: _saved != null,
          hasUnsavedChanges: true,
        ),
      );
      return true;
    }
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      LocalRichTextState(
        phase: LocalRichTextPhase.editing,
        body: _parent!.body,
        buffer: buffer,
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
            ? await store.createRichTextBuffer(
                expected: _parent!,
                buffer: edit,
                updatedAt: _now().toUtc(),
              )
            : await store.replaceRichTextBuffer(
                expected: previous,
                buffer: edit,
                updatedAt: _now().toUtc(),
              );
        if (saved == null) {
          _pending ??= edit;
          _halted = true;
          _failure(LocalRichTextPhase.conflict);
          return;
        }
        _saved = saved;
        _parent = saved.parent;
        _uncertainFinish = false;
      } on Object {
        _pending ??= edit;
        _halted = true;
        _failure(LocalRichTextPhase.saveFailed);
        return;
      }
    }
    if (_checkIdentity()) {
      _set(
        LocalRichTextState(
          phase: LocalRichTextPhase.editing,
          body: _parent!.body,
          buffer: _state.buffer,
          bufferAvailable: _saved != null,
          finishing: _finishing,
        ),
      );
    }
  }

  void _failure(LocalRichTextPhase phase) {
    if (!_checkIdentity()) return;
    _set(
      LocalRichTextState(
        phase: phase,
        body: _parent?.body,
        buffer: _state.buffer,
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
        _state.phase != LocalRichTextPhase.saveFailed ||
        _writer != null ||
        _pending == null) {
      return false;
    }
    _halted = false;
    _startWriter();
    if (!_checkIdentity() || _closing) return true;
    _set(
      LocalRichTextState(
        phase: LocalRichTextPhase.editing,
        body: _parent!.body,
        buffer: _state.buffer,
        bufferAvailable: _saved != null,
        saving: true,
        hasUnsavedChanges: true,
      ),
    );
    return true;
  }

  Future<LocalRichTextFlushResult> flush() async {
    if (!_checkIdentity()) {
      return _state.phase == LocalRichTextPhase.closed
          ? LocalRichTextFlushResult.closed
          : LocalRichTextFlushResult.obsolete;
    }
    while (_writer != null) {
      await _writer;
    }
    if (!_checkIdentity()) return LocalRichTextFlushResult.obsolete;
    return switch (_state.phase) {
      LocalRichTextPhase.editing => LocalRichTextFlushResult.saved,
      LocalRichTextPhase.saveFailed ||
      LocalRichTextPhase.actionFailed => LocalRichTextFlushResult.failed,
      LocalRichTextPhase.conflict => LocalRichTextFlushResult.conflict,
      _ => LocalRichTextFlushResult.notReady,
    };
  }

  /// Apply only after explicit confirmation. Invalid intermediate text remains
  /// saved as a buffer, and no validated body or publishing payload is made.
  Future<LocalRichTextFinishResult> apply({required bool confirmed}) =>
      _finish(confirmed: confirmed, apply: true);

  /// Discard only the buffer, never the parent recovery. If there is no buffer,
  /// finish without writing anything. A newer row is never deleted.
  Future<LocalRichTextFinishResult> discard({required bool confirmed}) =>
      _finish(confirmed: confirmed, apply: false);

  Future<LocalRichTextFinishResult> _finish({
    required bool confirmed,
    required bool apply,
  }) async {
    if (!confirmed ||
        !_canEdit ||
        _state.phase == LocalRichTextPhase.saveFailed ||
        _state.phase == LocalRichTextPhase.conflict) {
      return LocalRichTextFinishResult.notReady;
    }
    _finishing = true;
    final done = Completer<void>();
    _finishingDone = done;
    try {
      _set(
        LocalRichTextState(
          phase: _state.phase,
          body: _state.body,
          buffer: _state.buffer,
          bufferAvailable: _saved != null,
          saving: _writer != null,
          hasUnsavedChanges:
              _pending != null || _writer != null || _uncertainFinish,
          finishing: true,
        ),
      );
      if (_closing || !_checkIdentity()) {
        return LocalRichTextFinishResult.obsolete;
      }
      final flushed = await flush();
      if (_closing || !_checkIdentity()) {
        return LocalRichTextFinishResult.obsolete;
      }
      if (flushed == LocalRichTextFlushResult.conflict) {
        return LocalRichTextFinishResult.conflict;
      }
      // An earlier finish may have committed before reporting an error. A
      // deliberate action retry is safe only with its original CAS token;
      // flush must not claim that this uncertain outcome was saved.
      final retryingAction =
          _state.phase == LocalRichTextPhase.actionFailed &&
          _uncertainFinish &&
          _pending == null &&
          _writer == null;
      if (flushed != LocalRichTextFlushResult.saved && !retryingAction) {
        return LocalRichTextFinishResult.failed;
      }
      final saved = _saved;
      if (saved == null) {
        final parent = await store.load(key);
        if (_closing || !_checkIdentity()) {
          return LocalRichTextFinishResult.obsolete;
        }
        if (parent == null || !_sameSnapshot(parent, _parent!)) {
          _uncertainFinish = true;
          _failure(LocalRichTextPhase.conflict);
          return LocalRichTextFinishResult.conflict;
        }
        _set(
          LocalRichTextState(
            phase: LocalRichTextPhase.finished,
            body: parent.body,
          ),
        );
        return LocalRichTextFinishResult.finished;
      }
      if (apply) {
        try {
          saved.buffer.applyTo(saved.parent.body);
        } on FormatException {
          return LocalRichTextFinishResult.invalid;
        }
      }
      final result = apply
          ? await store.applyRichTextBuffer(
              expected: saved,
              updatedAt: _now().toUtc(),
            )
          : await store.discardRichTextBuffer(
              expected: saved,
              updatedAt: _now().toUtc(),
            );
      if (result == null) _uncertainFinish = true;
      if (!_checkIdentity()) return LocalRichTextFinishResult.obsolete;
      if (result == null) {
        _failure(LocalRichTextPhase.conflict);
        return LocalRichTextFinishResult.conflict;
      }
      _uncertainFinish = false;
      _parent = result;
      _saved = null;
      _set(
        LocalRichTextState(
          phase: LocalRichTextPhase.finished,
          body: result.body,
        ),
      );
      return LocalRichTextFinishResult.finished;
    } on Object {
      _uncertainFinish = true;
      if (_checkIdentity()) _failure(LocalRichTextPhase.actionFailed);
      return _invalidated
          ? LocalRichTextFinishResult.obsolete
          : LocalRichTextFinishResult.failed;
    } finally {
      _finishing = false;
      _finishingDone = null;
      if (_checkIdentity() && _state.finishing) {
        _set(
          LocalRichTextState(
            phase: _state.phase,
            body: _state.body,
            buffer: _state.buffer,
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
    if (_state.phase == LocalRichTextPhase.closed) return true;
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
    _expectedUnbufferedParent = null;
    _expectedBufferedRecovery = null;
    _set(const LocalRichTextState(phase: LocalRichTextPhase.closed));
    await _changes.close();
    return true;
  }
}

StructuredRichTextBuffer _initialBuffer(
  StructuredArticleDraft body,
  String blockId,
  int? itemIndex,
) {
  final probe = StructuredRichTextBuffer(
    blockId: blockId,
    itemIndex: itemIndex,
    runs: const [],
    selectionBase: -1,
    selectionExtent: -1,
    composingStart: -1,
    composingEnd: -1,
  );
  probe.validateTarget(body);
  final block = body.blocks.singleWhere((block) => block['id'] == blockId);
  final raw = itemIndex == null
      ? block['inlines'] as List
      : (block['itemInlines'] as List)[itemIndex] as List;
  return StructuredRichTextBuffer(
    blockId: blockId,
    itemIndex: itemIndex,
    runs: [
      for (final entry in raw)
        StructuredRichBufferRun(
          text: (entry as Map)['text'] as String,
          marks: entry.containsKey('marks')
              ? (entry['marks'] as List).cast<String>()
              : null,
          href: entry['href'] as String?,
        ),
    ],
    selectionBase: -1,
    selectionExtent: -1,
    composingStart: -1,
    composingEnd: -1,
  );
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
