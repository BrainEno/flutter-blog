import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/local_buffer_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared engine behind both local buffer sessions (#291), driven through
/// a minimal in-memory port. The SQLite-backed text and rich-text suites cover
/// the real stores; this one pins the two switches that are the only
/// behavioural difference between them, and the generic contract both rely on.

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-id',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);

StructuredArticleDraft _draft(String text) => StructuredArticleDraft.parse(
  version: 0,
  blocks: [
    {'id': 'p', 'type': 'paragraph', 'text': text},
  ],
);

StructuredBodyRecovery _parent({int revision = 1, String text = 'body'}) =>
    StructuredBodyRecovery(
      key: _key,
      backendStorageKey: 'https://api.example.invalid',
      rowId: 7,
      revision: revision,
      base: _draft('base'),
      body: _draft(text),
      updatedAt: DateTime.utc(2026, 11, 19),
      baseStorageJson: 'base',
      bodyStorageJson: 'body-$revision',
    );

/// A buffered recovery: the parent it was written against, the target block
/// and the buffered text.
class _Saved {
  _Saved(this.parent, this.target, this.text);
  final StructuredBodyRecovery parent;
  final String target;
  final String text;
  String get storageJson => '$target:$text';
}

class _State extends LocalBufferState<String> {
  const _State({
    required super.phase,
    super.body,
    this.text,
    super.bufferAvailable,
    super.saving,
    super.hasUnsavedChanges,
    super.finishing,
  });

  final String? text;

  @override
  String? get value => text;
}

class _Identity implements NowaveSessionIdentity {
  final events = StreamController<void>.broadcast(sync: true);
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 1;
  @override
  Stream<void> get identityChanges => events.stream;

  void signOut() {
    activeUserId = null;
    accessToken = null;
    sessionGeneration++;
    events.add(null);
  }
}

class _Recoveries implements StructuredBodyRecoveryStore {
  StructuredBodyRecovery? current = _parent();
  int loads = 0;
  Object? loadError;

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) async {
    loads++;
    final error = loadError;
    if (error != null) throw error;
    return current;
  }

  @override
  Future<StructuredBodyRecovery?> create({
    required StructuredBodyKey key,
    required StructuredArticleDraft base,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? sessionMetadata,
  }) => throw UnimplementedError();

  @override
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  }) => throw UnimplementedError();

  @override
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  }) => throw UnimplementedError();

  @override
  Future<bool> discard(StructuredBodyRecovery expected) =>
      throw UnimplementedError();
}

class _Port implements LocalBufferPort<String, String, _Saved, _State> {
  _Port(this.recoveries);

  final _Recoveries recoveries;
  _Saved? stored;
  final writes = <String>[];
  int applies = 0;
  int discards = 0;

  @override
  Future<_Saved?> loadBuffer(StructuredBodyKey key) async => stored;

  @override
  Future<_Saved?> createBuffer({
    required StructuredBodyRecovery expected,
    required String buffer,
    required DateTime updatedAt,
  }) async {
    writes.add(buffer);
    return stored = _Saved(expected, 'p', buffer);
  }

  @override
  Future<_Saved?> replaceBuffer({
    required _Saved expected,
    required String buffer,
    required DateTime updatedAt,
  }) async {
    writes.add(buffer);
    if (!identical(expected, stored)) return null;
    return stored = _Saved(expected.parent, 'p', buffer);
  }

  @override
  Future<StructuredBodyRecovery?> applyBuffer({
    required _Saved expected,
    required DateTime updatedAt,
  }) async {
    applies++;
    stored = null;
    final applied = _parent(revision: 2, text: expected.text);
    recoveries.current = applied;
    return applied;
  }

  @override
  Future<StructuredBodyRecovery?> discardBuffer({
    required _Saved expected,
    required DateTime updatedAt,
  }) async {
    discards++;
    stored = null;
    return expected.parent;
  }

  @override
  StructuredBodyRecovery parentOf(_Saved recovery) => recovery.parent;

  @override
  String bufferOf(_Saved recovery) => recovery.text;

  @override
  String storageJsonOf(_Saved recovery) => recovery.storageJson;

  @override
  bool targetsThis(String buffer) => !buffer.startsWith('elsewhere:');

  @override
  String initialValue(StructuredBodyRecovery parent, _Saved? saved) =>
      saved?.text ?? parent.body.blocks.single['text'] as String;

  @override
  String bufferForEdit(String value, StructuredArticleDraft body) {
    if (value.length > 10) throw ArgumentError('Too long');
    return value;
  }

  @override
  void checkApplicable(String buffer, StructuredArticleDraft body) {
    if (buffer.isEmpty) throw const FormatException('Empty paragraph');
  }

  @override
  _State state({
    required LocalBufferPhase phase,
    StructuredArticleDraft? body,
    String? value,
    bool bufferAvailable = false,
    bool saving = false,
    bool hasUnsavedChanges = false,
    bool finishing = false,
  }) => _State(
    phase: phase,
    body: body,
    text: value,
    bufferAvailable: bufferAvailable,
    saving: saving,
    hasUnsavedChanges: hasUnsavedChanges,
    finishing: finishing,
  );
}

void main() {
  late _Recoveries recoveries;
  late _Port port;
  late _Identity identity;

  setUp(() {
    recoveries = _Recoveries();
    port = _Port(recoveries);
    identity = _Identity();
  });

  LocalBufferSession<String, String, _Saved, _State> session({
    bool requireToken = false,
    bool verifyEmptyFinish = false,
    int rowId = 7,
    StructuredBodyRecovery? expectedParent,
    _Saved? expectedBuffer,
  }) => LocalBufferSession(
    key: _key,
    selectedRowId: rowId,
    fence: _fence,
    identity: identity,
    recoveries: recoveries,
    port: port,
    requireExpectedToken: requireToken,
    verifyParentBeforeEmptyFinish: verifyEmptyFinish,
    expectedUnbufferedParent: expectedParent,
    expectedBufferedRecovery: expectedBuffer,
    now: () => DateTime.utc(2026, 11, 19, 12),
  );

  group('selected recovery tokens', () {
    test('a row id must be positive', () {
      expect(() => session(rowId: 0), throwsArgumentError);
    });

    test('both tokens at once are never accepted', () {
      expect(
        () => session(
          expectedParent: _parent(),
          expectedBuffer: _Saved(_parent(), 'p', 'x'),
        ),
        throwsArgumentError,
      );
    });

    test('a required token must be supplied', () {
      expect(() => session(requireToken: true), throwsArgumentError);
      expect(
        session(requireToken: true, expectedParent: _parent()),
        isA<LocalBufferSession<String, String, _Saved, _State>>(),
      );
    });

    test('an optional token may be omitted', () {
      expect(session().state.phase, LocalBufferPhase.initial);
    });
  });

  group('open', () {
    test('offers the parent body for an explicit choice', () async {
      final s = session();
      await s.open();

      expect(s.state.phase, LocalBufferPhase.recoveryChoice);
      expect(s.state.value, 'body');
      expect(s.state.bufferAvailable, isFalse);
      expect(port.writes, isEmpty);
    });

    test('prefers a saved buffer and says one is available', () async {
      port.stored = _Saved(_parent(), 'p', 'draft');
      final s = session();
      await s.open();

      expect(s.state.value, 'draft');
      expect(s.state.bufferAvailable, isTrue);
      // The buffer carries its parent; no second read is needed.
      expect(recoveries.loads, 0);
    });

    test('a buffer for another target is a conflict, not a loss', () async {
      port.stored = _Saved(_parent(), 'p', 'elsewhere:draft');
      final s = session();
      await s.open();

      expect(s.state.phase, LocalBufferPhase.conflict);
      expect(s.state.bufferAvailable, isTrue);
    });

    test('a recreated row is a conflict', () async {
      final s = session(rowId: 8);
      await s.open();

      expect(s.state.phase, LocalBufferPhase.conflict);
    });

    test('an unbuffered token rejects a changed parent', () async {
      final s = session(expectedParent: _parent(revision: 0));
      await s.open();

      expect(s.state.phase, LocalBufferPhase.conflict);
    });

    test('a buffered token rejects a different buffer', () async {
      port.stored = _Saved(_parent(), 'p', 'draft');
      final s = session(expectedBuffer: _Saved(_parent(), 'p', 'other'));
      await s.open();

      expect(s.state.phase, LocalBufferPhase.conflict);
    });

    test('a missing recovery is a conflict', () async {
      recoveries.current = null;
      final s = session();
      await s.open();

      expect(s.state.phase, LocalBufferPhase.conflict);
    });

    test('a failed read is a load failure', () async {
      recoveries.loadError = StateError('disk');
      final s = session();
      await s.open();

      expect(s.state.phase, LocalBufferPhase.loadFailed);
    });
  });

  group('editing', () {
    test('edits are written in order and applied on request', () async {
      final s = session();
      await s.open();
      expect(s.resume(), isTrue);

      expect(s.edit('one'), isTrue);
      expect(s.state.saving, isTrue);
      expect(s.edit('two'), isTrue);
      expect(await s.flush(), LocalBufferFlushResult.saved);
      expect(port.writes.last, 'two');
      expect(s.state.bufferAvailable, isTrue);

      expect(await s.apply(confirmed: false), LocalBufferFinishResult.notReady);
      expect(await s.apply(confirmed: true), LocalBufferFinishResult.finished);
      expect(s.state.phase, LocalBufferPhase.finished);
      expect(s.state.body!.blocks.single['text'], 'two');
      expect(port.applies, 1);
    });

    test('an out-of-bounds value throws before anything changes', () async {
      final s = session();
      await s.open();
      s.resume();

      expect(() => s.edit('far too long a value'), throwsArgumentError);
      expect(s.state.saving, isFalse);
      expect(port.writes, isEmpty);
    });

    test('an inapplicable buffer stays saved and reports invalid', () async {
      final s = session();
      await s.open();
      s.resume();
      s.edit('');
      await s.flush();

      expect(await s.apply(confirmed: true), LocalBufferFinishResult.invalid);
      expect(port.stored?.text, '');
      expect(s.state.phase, LocalBufferPhase.editing);
      expect(s.state.finishing, isFalse);
    });

    test('discard drops the buffer and keeps the parent', () async {
      final s = session();
      await s.open();
      s.resume();
      s.edit('gone');
      await s.flush();

      expect(
        await s.discard(confirmed: true),
        LocalBufferFinishResult.finished,
      );
      expect(port.discards, 1);
      expect(s.state.body!.blocks.single['text'], 'body');
    });
  });

  group('finishing without a buffer', () {
    test('trusts the opened parent when not asked to verify', () async {
      final s = session();
      await s.open();
      s.resume();
      recoveries.current = _parent(revision: 5, text: 'elsewhere');
      final loadsBefore = recoveries.loads;

      expect(
        await s.discard(confirmed: true),
        LocalBufferFinishResult.finished,
      );
      expect(recoveries.loads, loadsBefore);
      expect(s.state.body!.blocks.single['text'], 'body');
    });

    test('re-reads the parent when asked to verify', () async {
      final s = session(verifyEmptyFinish: true);
      await s.open();
      s.resume();

      expect(
        await s.discard(confirmed: true),
        LocalBufferFinishResult.finished,
      );
      expect(recoveries.loads, 2);
    });

    test('a parent changed elsewhere is an uncertain conflict', () async {
      final s = session(verifyEmptyFinish: true);
      await s.open();
      s.resume();
      recoveries.current = _parent(revision: 5, text: 'elsewhere');

      expect(
        await s.discard(confirmed: true),
        LocalBufferFinishResult.conflict,
      );
      expect(s.state.phase, LocalBufferPhase.conflict);
      expect(s.state.hasUnsavedChanges, isTrue);
      // The uncertain outcome needs an explicit acknowledgement to close.
      expect(await s.close(), isFalse);
      expect(await s.close(abandonUnsaved: true), isTrue);
      expect(s.state.phase, LocalBufferPhase.closed);
    });
  });

  group('identity', () {
    test('a sign-out invalidates the session and refuses input', () async {
      final s = session();
      final phases = <LocalBufferPhase>[];
      final sub = s.changes.listen((state) => phases.add(state.phase));
      await s.open();
      s.resume();

      identity.signOut();

      expect(phases.last, LocalBufferPhase.invalidated);
      expect(s.state.value, isNull);
      expect(s.edit('late'), isFalse);
      expect(await s.flush(), LocalBufferFlushResult.obsolete);
      await sub.cancel();
      expect(await s.close(), isTrue);
    });

    test('closing twice is harmless', () async {
      final s = session();
      await s.open();
      expect(await s.close(), isTrue);
      expect(await s.close(), isTrue);
      expect(await s.flush(), LocalBufferFlushResult.closed);
    });
  });
}
