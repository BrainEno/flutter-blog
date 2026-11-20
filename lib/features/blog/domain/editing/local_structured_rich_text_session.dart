import 'package:belog/features/blog/domain/editing/local_buffer_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_session_store.dart';

/// The rich-text session's names for the shared state machine (#291).
typedef LocalRichTextPhase = LocalBufferPhase;
typedef LocalRichTextFlushResult = LocalBufferFlushResult;
typedef LocalRichTextFinishResult = LocalBufferFinishResult;

/// Local snapshots only. An intermediate value is never a server body. Values
/// already delivered to a consumer cannot be revoked on identity changes.
class LocalRichTextState extends LocalBufferState<StructuredRichTextBuffer> {
  const LocalRichTextState({
    required super.phase,
    super.body,
    this.buffer,
    super.bufferAvailable,
    super.saving,
    super.hasUnsavedChanges,
    super.finishing,
  });

  /// The formatted runs, selection and composing range of the target.
  final StructuredRichTextBuffer? buffer;

  @override
  StructuredRichTextBuffer? get value => buffer;
}

/// Coordinates a single explicitly selected formatted target in one existing
/// local recovery. Exact preselected parent or buffered tokens are mandatory;
/// list indices are never reopened using only a row ID. No network or UI is
/// involved. Consumers must reopen the row after finish and fence their route.
/// Accepted writes can finish only under their original account and backend.
/// Input not durably saved may be lost after process death or abandonment.
///
/// The state machine, identity fence and writer live in [LocalBufferSession];
/// this class supplies the rich-text buffer. Finishing without a buffer
/// re-reads the parent and reports a conflict if it changed meanwhile.
class LocalStructuredRichTextSession
    extends
        LocalBufferSession<
          StructuredRichTextBuffer,
          StructuredRichTextBuffer,
          StructuredRichTextBufferRecovery,
          LocalRichTextState
        > {
  LocalStructuredRichTextSession({
    required super.key,
    required super.selectedRowId,
    required this.blockId,
    required this.itemIndex,
    required super.fence,
    required super.identity,
    required this.store,
    super.expectedUnbufferedParent,
    super.expectedBufferedRecovery,
    super.now,
  }) : super(
         recoveries: store,
         port: _RichTextPort(store, blockId, itemIndex),
         requireExpectedToken: true,
         verifyParentBeforeEmptyFinish: true,
       );

  final String blockId;
  final int? itemIndex;
  final StructuredRichTextSessionStore store;
}

final class _RichTextPort
    implements
        LocalBufferPort<
          StructuredRichTextBuffer,
          StructuredRichTextBuffer,
          StructuredRichTextBufferRecovery,
          LocalRichTextState
        > {
  _RichTextPort(this._store, this._blockId, this._itemIndex);

  final StructuredRichTextSessionStore _store;
  final String _blockId;
  final int? _itemIndex;

  @override
  Future<StructuredRichTextBufferRecovery?> loadBuffer(StructuredBodyKey key) =>
      _store.loadRichTextBuffer(key);

  @override
  Future<StructuredRichTextBufferRecovery?> createBuffer({
    required StructuredBodyRecovery expected,
    required StructuredRichTextBuffer buffer,
    required DateTime updatedAt,
  }) => _store.createRichTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );

  @override
  Future<StructuredRichTextBufferRecovery?> replaceBuffer({
    required StructuredRichTextBufferRecovery expected,
    required StructuredRichTextBuffer buffer,
    required DateTime updatedAt,
  }) => _store.replaceRichTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );

  @override
  Future<StructuredBodyRecovery?> applyBuffer({
    required StructuredRichTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => _store.applyRichTextBuffer(expected: expected, updatedAt: updatedAt);

  @override
  Future<StructuredBodyRecovery?> discardBuffer({
    required StructuredRichTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => _store.discardRichTextBuffer(expected: expected, updatedAt: updatedAt);

  @override
  StructuredBodyRecovery parentOf(StructuredRichTextBufferRecovery recovery) =>
      recovery.parent;

  @override
  StructuredRichTextBuffer bufferOf(
    StructuredRichTextBufferRecovery recovery,
  ) => recovery.buffer;

  @override
  String storageJsonOf(StructuredRichTextBufferRecovery recovery) =>
      recovery.storageJson;

  @override
  bool targetsThis(StructuredRichTextBuffer buffer) =>
      buffer.blockId == _blockId && buffer.itemIndex == _itemIndex;

  @override
  StructuredRichTextBuffer initialValue(
    StructuredBodyRecovery parent,
    StructuredRichTextBufferRecovery? saved,
  ) {
    final buffer =
        saved?.buffer ?? _initialBuffer(parent.body, _blockId, _itemIndex);
    buffer.validateTarget(parent.body);
    return buffer;
  }

  @override
  StructuredRichTextBuffer bufferForEdit(
    StructuredRichTextBuffer value,
    StructuredArticleDraft body,
  ) {
    if (!targetsThis(value)) {
      throw ArgumentError('Rich buffer target changed');
    }
    value.validateTarget(body);
    return value;
  }

  @override
  void checkApplicable(
    StructuredRichTextBuffer buffer,
    StructuredArticleDraft body,
  ) {
    buffer.applyTo(body);
  }

  @override
  LocalRichTextState state({
    required LocalBufferPhase phase,
    StructuredArticleDraft? body,
    StructuredRichTextBuffer? value,
    bool bufferAvailable = false,
    bool saving = false,
    bool hasUnsavedChanges = false,
    bool finishing = false,
  }) => LocalRichTextState(
    phase: phase,
    body: body,
    buffer: value,
    bufferAvailable: bufferAvailable,
    saving: saving,
    hasUnsavedChanges: hasUnsavedChanges,
    finishing: finishing,
  );
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
