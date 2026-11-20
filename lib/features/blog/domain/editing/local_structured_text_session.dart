import 'package:belog/features/blog/domain/editing/local_buffer_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';

/// The plain-text session's names for the shared state machine (#291).
typedef LocalTextPhase = LocalBufferPhase;
typedef LocalTextFlushResult = LocalBufferFlushResult;
typedef LocalTextFinishResult = LocalBufferFinishResult;

/// Local snapshots only. An intermediate value is never a server body. Values
/// already delivered to a consumer cannot be revoked on identity changes.
class LocalTextState extends LocalBufferState<String> {
  const LocalTextState({
    required super.phase,
    super.body,
    this.text,
    super.bufferAvailable,
    super.saving,
    super.hasUnsavedChanges,
    super.finishing,
  });

  /// The plain text of the target block.
  final String? text;

  @override
  String? get value => text;
}

/// Coordinates one plain-text target in an existing, explicitly selected local
/// recovery. It does not contact the server, create a parent recovery, publish,
/// or adopt a snapshot into another editing session. On completion, consumers
/// must reopen the recovery using its new CAS revision before editing the body.
///
/// Only unformatted text targets are supported. Recovery is always a decision
/// even without a saved buffer. The state machine, identity fence and writer
/// live in [LocalBufferSession]; this class supplies the plain-text buffer
/// and keeps the original public names.
///
/// Unlike the rich-text session a preselected token is optional here, and a
/// finish without any buffer reports the body opened at the choice without
/// re-reading it - both as before #291.
class LocalStructuredTextSession
    extends
        LocalBufferSession<
          String,
          StructuredTextBuffer,
          StructuredTextBufferRecovery,
          LocalTextState
        > {
  LocalStructuredTextSession({
    required super.key,
    required super.selectedRowId,
    required this.blockId,
    required super.fence,
    required super.identity,
    required this.store,
    this.expectedUnbufferedParent,
    this.expectedBufferedRecovery,
    super.now,
  }) : super(
         recoveries: store,
         port: _TextPort(store, blockId),
         requireExpectedToken: false,
         verifyParentBeforeEmptyFinish: false,
         expectedUnbufferedParent: expectedUnbufferedParent,
         expectedBufferedRecovery: expectedBufferedRecovery,
       );

  final String blockId;
  final StructuredTextSessionStore store;

  /// When handed off from a body editor, require the precise unbuffered
  /// snapshot that editor closed with, not merely the same row incarnation.
  /// Ordinary recovery opens may omit this and still require explicit consent.
  final StructuredBodyRecovery? expectedUnbufferedParent;

  /// For an explicitly selected indexed buffer, require the same exact raw
  /// buffer and parent snapshot at open. Null is not an absent-buffer claim.
  final StructuredTextBufferRecovery? expectedBufferedRecovery;
}

final class _TextPort
    implements
        LocalBufferPort<
          String,
          StructuredTextBuffer,
          StructuredTextBufferRecovery,
          LocalTextState
        > {
  _TextPort(this._store, this._blockId);

  final StructuredTextSessionStore _store;
  final String _blockId;

  @override
  Future<StructuredTextBufferRecovery?> loadBuffer(StructuredBodyKey key) =>
      _store.loadTextBuffer(key);

  @override
  Future<StructuredTextBufferRecovery?> createBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) => _store.createTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );

  @override
  Future<StructuredTextBufferRecovery?> replaceBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) => _store.replaceTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );

  @override
  Future<StructuredBodyRecovery?> applyBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => _store.applyTextBuffer(expected: expected, updatedAt: updatedAt);

  @override
  Future<StructuredBodyRecovery?> discardBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => _store.discardTextBuffer(expected: expected, updatedAt: updatedAt);

  @override
  StructuredBodyRecovery parentOf(StructuredTextBufferRecovery recovery) =>
      recovery.parent;

  @override
  StructuredTextBuffer bufferOf(StructuredTextBufferRecovery recovery) =>
      recovery.buffer;

  @override
  String storageJsonOf(StructuredTextBufferRecovery recovery) =>
      recovery.storageJson;

  @override
  bool targetsThis(StructuredTextBuffer buffer) => buffer.blockId == _blockId;

  @override
  String initialValue(
    StructuredBodyRecovery parent,
    StructuredTextBufferRecovery? saved,
  ) {
    final target = StructuredTextBuffer(blockId: _blockId, text: '');
    target.validateTarget(parent.body);
    return saved?.buffer.text ??
        parent.body.blocks.singleWhere(
              (block) => block['id'] == _blockId,
            )['text']
            as String;
  }

  @override
  StructuredTextBuffer bufferForEdit(
    String value,
    StructuredArticleDraft body,
  ) {
    final buffer = StructuredTextBuffer(blockId: _blockId, text: value);
    buffer.validateTarget(body);
    return buffer;
  }

  @override
  void checkApplicable(
    StructuredTextBuffer buffer,
    StructuredArticleDraft body,
  ) {
    buffer.applyTo(body);
  }

  @override
  LocalTextState state({
    required LocalBufferPhase phase,
    StructuredArticleDraft? body,
    String? value,
    bool bufferAvailable = false,
    bool saving = false,
    bool hasUnsavedChanges = false,
    bool finishing = false,
  }) => LocalTextState(
    phase: phase,
    body: body,
    text: value,
    bufferAvailable: bufferAvailable,
    saving: saving,
    hasUnsavedChanges: hasUnsavedChanges,
    finishing: finishing,
  );
}
