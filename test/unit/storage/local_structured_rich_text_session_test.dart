import 'dart:async';
import 'dart:io';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_rich_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_session_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/open_indexed_rich_text_recovery.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-id',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _time = DateTime.utc(2026, 10, 29);
final _backend = Uri.parse('https://example.invalid/v1');

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredRichTextBuffer _buffer(
  String text, {
  String id = 'heading',
  int? item,
  int base = -1,
  int extent = -1,
  int start = -1,
  int end = -1,
}) => StructuredRichTextBuffer(
  blockId: id,
  itemIndex: item,
  runs: [
    StructuredRichBufferRun(text: text, marks: ['bold'], href: '/guide'),
  ],
  selectionBase: base,
  selectionExtent: extent,
  composingStart: start,
  composingEnd: end,
);

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

  void change(String? user) {
    activeUserId = user;
    accessToken = user == null ? null : 'other-token';
    sessionGeneration++;
    events.add(null);
  }
}

/// Gates are deliberately outside the actual SQLite transaction. This allows
/// two real store instances to race without holding a database lock in a test.
class _ControlledStore implements StructuredRichTextSessionStore {
  _ControlledStore(this.inner);
  final StructuredRichTextSessionStore inner;
  Completer<void>? loadGate;
  Completer<void>? parentLoadGate;
  Completer<void>? writeGate;
  Completer<void>? finishGate;
  final loadStarted = Completer<void>();
  final parentLoadStarted = Completer<void>();
  final writeStarted = Completer<void>();
  final finishStarted = Completer<void>();
  Object? loadError;
  Object? writeError;
  Object? finishError;
  bool failAfterWrite = false;
  bool failAfterFinish = false;
  int loads = 0;
  int creates = 0;
  int replacements = 0;
  int applies = 0;
  int discards = 0;
  void Function()? onWrite;

  @override
  Future<StructuredRichTextBufferRecovery?> loadRichTextBuffer(
    StructuredBodyKey key,
  ) async {
    loads++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    if (loadGate case final gate?) await gate.future;
    if (loadError case final error?) throw error;
    return inner.loadRichTextBuffer(key);
  }

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) async {
    if (!parentLoadStarted.isCompleted) parentLoadStarted.complete();
    if (parentLoadGate case final gate?) await gate.future;
    return inner.load(key);
  }

  Future<void> _beforeWrite() async {
    onWrite?.call();
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate case final gate?) await gate.future;
    if (writeError case final error?) throw error;
  }

  @override
  Future<StructuredRichTextBufferRecovery?> createRichTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredRichTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    creates++;
    await _beforeWrite();
    final result = await inner.createRichTextBuffer(
      expected: expected,
      buffer: buffer,
      updatedAt: updatedAt,
    );
    if (failAfterWrite) throw StateError('ambiguous commit');
    return result;
  }

  @override
  Future<StructuredRichTextBufferRecovery?> replaceRichTextBuffer({
    required StructuredRichTextBufferRecovery expected,
    required StructuredRichTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    replacements++;
    await _beforeWrite();
    final result = await inner.replaceRichTextBuffer(
      expected: expected,
      buffer: buffer,
      updatedAt: updatedAt,
    );
    if (failAfterWrite) throw StateError('ambiguous commit');
    return result;
  }

  Future<void> _beforeFinish() async {
    if (!finishStarted.isCompleted) finishStarted.complete();
    if (finishGate case final gate?) await gate.future;
    if (finishError case final error?) throw error;
  }

  @override
  Future<StructuredBodyRecovery?> applyRichTextBuffer({
    required StructuredRichTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    applies++;
    await _beforeFinish();
    final result = await inner.applyRichTextBuffer(
      expected: expected,
      updatedAt: updatedAt,
    );
    if (failAfterFinish) throw StateError('ambiguous finish');
    return result;
  }

  @override
  Future<StructuredBodyRecovery?> discardRichTextBuffer({
    required StructuredRichTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    discards++;
    await _beforeFinish();
    return inner.discardRichTextBuffer(
      expected: expected,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<StructuredBodyRecovery?> create({
    required StructuredBodyKey key,
    required StructuredArticleDraft base,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? sessionMetadata,
  }) => inner.create(
    key: key,
    base: base,
    body: body,
    updatedAt: updatedAt,
    baseMetadata: baseMetadata,
    sessionMetadata: sessionMetadata,
  );
  @override
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  }) => inner.replace(expected: expected, body: body, updatedAt: updatedAt);
  @override
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  }) => inner.replaceSession(
    expected: expected,
    body: body,
    sessionMetadata: sessionMetadata,
    updatedAt: updatedAt,
  );
  @override
  Future<bool> discard(StructuredBodyRecovery expected) =>
      inner.discard(expected);
}

class _Harness {
  _Harness({AppDatabase? database}) {
    db = database ?? AppDatabase(NativeDatabase.memory());
    inner = SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: _backend);
    controlled = _ControlledStore(inner);
    identity = _Identity();
  }
  late final AppDatabase db;
  late final SqliteStructuredBodyRecoveryStore inner;
  late final _ControlledStore controlled;
  late final _Identity identity;
  final sessions = <LocalStructuredRichTextSession>[];

  Future<StructuredBodyRecovery> create({StructuredBodyKey? key}) async =>
      (await inner.create(
        key: key ?? _key,
        base: _body(),
        body: _body(),
        updatedAt: _time,
      ))!;

  LocalStructuredRichTextSession session(
    StructuredBodyRecovery parent, {
    String block = 'heading',
    int? item,
    StructuredRichTextBufferRecovery? saved,
    StructuredBodyKey? key,
    NowaveSessionFence fence = _fence,
    StructuredRichTextSessionStore? store,
  }) {
    final result = LocalStructuredRichTextSession(
      key: key ?? _key,
      selectedRowId: parent.rowId,
      blockId: block,
      itemIndex: item,
      expectedUnbufferedParent: saved == null ? parent : null,
      expectedBufferedRecovery: saved,
      fence: fence,
      identity: identity,
      store: store ?? controlled,
      now: () => _time,
    );
    sessions.add(result);
    return result;
  }

  Future<LocalStructuredRichTextSession> editing({
    StructuredBodyRecovery? parent,
  }) async {
    final session = this.session(parent ?? await create());
    await session.open();
    expect(session.resume(), isTrue);
    return session;
  }

  Future<void> dispose() async {
    for (final session in sessions) {
      await session.close(abandonUnsaved: true);
    }
    await identity.events.close();
    await db.close();
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  test(
    'exact selection and explicit choice preserve all initial formatting',
    () async {
      final parent = await h.create();
      final session = h.session(parent);
      expect(session.edit(_buffer('early')), isFalse);
      await session.open();
      expect(session.state.phase, LocalRichTextPhase.recoveryChoice);
      final buffer = session.state.buffer!;
      expect(buffer.text, 'Bold代码');
      expect(buffer.runs.first.marks, [
        'bold',
        'italic',
        'underline',
        'strikethrough',
      ]);
      expect(buffer.runs.first.href, '/guide');
      expect(buffer.selectionBase, -1);
      expect(buffer.composingStart, -1);
      expect(session.edit(_buffer('early')), isFalse);
      expect(session.resume(), isTrue);
      expect(await session.flush(), LocalRichTextFlushResult.saved);
      expect(await h.inner.loadRichTextBuffer(_key), isNull);
    },
  );

  test('list target retains absent marks and cannot retarget', () async {
    final parent = await h.create();
    final session = h.session(parent, block: 'list', item: 0);
    await session.open();
    expect(session.state.buffer!.text, 'First item');
    expect(session.state.buffer!.runs.last.marks, isNull);
    expect(session.resume(), isTrue);
    expect(() => session.edit(_buffer('wrong')), throwsArgumentError);
    expect(
      () => session.edit(_buffer('wrong', id: 'list', item: 1)),
      throwsArgumentError,
    );
    expect(await h.inner.loadRichTextBuffer(_key), isNull);
  });

  test(
    'invalid target or absent inlines never produce a writable session',
    () async {
      final parent = await h.create();
      for (final session in [
        h.session(parent, block: 'paragraph'),
        h.session(parent, block: 'list', item: 9),
        h.session(parent, block: 'image-one'),
      ]) {
        await session.open();
        expect(session.state.phase, LocalRichTextPhase.loadFailed);
        expect(session.resume(), isFalse);
      }
    },
  );

  test('stale exact parent cannot silently redirect an indexed item', () async {
    final parent = await h.create();
    final changed = (await h.inner.replace(
      expected: parent,
      body: parent.body,
      updatedAt: _time.add(const Duration(seconds: 1)),
    ))!;
    expect(changed.revision, greaterThan(parent.revision));
    final session = h.session(parent, block: 'list', item: 0);
    await session.open();
    expect(session.state.phase, LocalRichTextPhase.conflict);
    expect(await h.inner.loadRichTextBuffer(_key), isNull);
  });

  test('buffer choice, cancel, and reopen use exact raw token', () async {
    final parent = await h.create();
    final saved = (await h.inner.createRichTextBuffer(
      expected: parent,
      buffer: _buffer(''),
      updatedAt: _time,
    ))!;
    final session = h.session(parent, saved: saved);
    await session.open();
    expect(session.state.phase, LocalRichTextPhase.recoveryChoice);
    expect(session.state.buffer!.text, '');
    expect(session.state.bufferAvailable, isTrue);
    expect(session.cancel(), isTrue);
    expect(
      (await h.inner.loadRichTextBuffer(_key))!.storageJson,
      saved.storageJson,
    );
    final reopened = h.session(parent, saved: saved);
    await reopened.open();
    expect(reopened.resume(), isTrue);
    expect(
      await reopened.apply(confirmed: true),
      LocalRichTextFinishResult.invalid,
    );
    expect(
      (await h.inner.loadRichTextBuffer(_key))!.storageJson,
      saved.storageJson,
    );
  });

  test('changed raw buffered token conflicts before recovery', () async {
    final parent = await h.create();
    final saved = (await h.inner.createRichTextBuffer(
      expected: parent,
      buffer: _buffer('first'),
      updatedAt: _time,
    ))!;
    await h.inner.replaceRichTextBuffer(
      expected: saved,
      buffer: _buffer('newer'),
      updatedAt: _time,
    );
    final session = h.session(parent, saved: saved);
    await session.open();
    expect(session.state.phase, LocalRichTextPhase.conflict);
    expect((await h.inner.loadRichTextBuffer(_key))!.buffer.text, 'newer');
  });

  test(
    'serialized writes coalesce and persist last selection and composition',
    () async {
      final session = await h.editing();
      final gate = h.controlled.writeGate = Completer<void>();
      session.edit(_buffer('first'));
      await h.controlled.writeStarted.future;
      session.edit(_buffer('second'));
      session.edit(_buffer('latest', base: 6, extent: 1, start: 1, end: 4));
      gate.complete();
      expect(await session.flush(), LocalRichTextFlushResult.saved);
      final saved = (await h.inner.loadRichTextBuffer(_key))!.buffer;
      expect(saved.text, 'latest');
      expect(saved.selectionBase, 6);
      expect(saved.selectionExtent, 1);
      expect(saved.composingStart, 1);
      expect(h.controlled.creates, 1);
      expect(h.controlled.replacements, 1);
      expect(
        await session.apply(confirmed: true),
        LocalRichTextFinishResult.invalid,
      );
      expect(
        (await h.inner.loadRichTextBuffer(_key))!.buffer.encode(),
        saved.encode(),
      );
    },
  );

  test(
    'UTF-16 unmatched units survive saving even if final body is invalid',
    () async {
      final session = await h.editing();
      final bad = String.fromCharCodes([0xd800]);
      final value = _buffer(bad, base: 1, extent: 1);
      session.edit(value);
      expect(await session.flush(), LocalRichTextFlushResult.saved);
      expect(
        (await h.inner.loadRichTextBuffer(_key))!.buffer.encode(),
        value.encode(),
      );
      expect(
        await session.apply(confirmed: true),
        LocalRichTextFinishResult.invalid,
      );
    },
  );

  test(
    'confirmation applies only target and retains surrounding blocks',
    () async {
      final parent = await h.create();
      final session = await h.editing(parent: parent);
      session.edit(_buffer('Changed', base: 7, extent: 7));
      expect(
        await session.apply(confirmed: false),
        LocalRichTextFinishResult.notReady,
      );
      expect(
        await session.apply(confirmed: true),
        LocalRichTextFinishResult.finished,
      );
      final body = (await h.inner.load(_key))!.body;
      expect(body.blocks[0]['text'], 'Changed');
      expect(body.blocks[1], parent.body.blocks[1]);
      expect(body.blocks[4], parent.body.blocks[4]);
      expect(await h.inner.loadRichTextBuffer(_key), isNull);
    },
  );

  test('discard flushes latest and restores original parent body', () async {
    final parent = await h.create();
    final session = await h.editing(parent: parent);
    session.edit(_buffer('temporary'));
    expect(
      await session.discard(confirmed: false),
      LocalRichTextFinishResult.notReady,
    );
    expect(
      await session.discard(confirmed: true),
      LocalRichTextFinishResult.finished,
    );
    expect(
      (await h.inner.load(_key))!.body.toJsonBlocks(),
      parent.body.toJsonBlocks(),
    );
    expect(await h.inner.loadRichTextBuffer(_key), isNull);
  });

  test('no-op finish refuses a changed parent after selection', () async {
    final parent = await h.create();
    final session = await h.editing(parent: parent);
    await h.inner.replace(
      expected: parent,
      body: parent.body,
      updatedAt: _time.add(const Duration(seconds: 1)),
    );
    expect(
      await session.apply(confirmed: true),
      LocalRichTextFinishResult.conflict,
    );
    expect(session.state.body, isNotNull);
  });

  test(
    'racing rich editors preserve winner without implicit conflict retry',
    () async {
      final parent = await h.create();
      final first = await h.editing(parent: parent);
      final second = await h.editing(parent: parent);
      first.edit(_buffer('winner'));
      expect(await first.flush(), LocalRichTextFlushResult.saved);
      second.edit(_buffer('loser'));
      expect(await second.flush(), LocalRichTextFlushResult.conflict);
      expect(second.state.buffer!.text, 'loser');
      expect(second.retrySave(), isFalse);
      second.edit(_buffer('later input'));
      expect((await h.inner.loadRichTextBuffer(_key))!.buffer.text, 'winner');
      expect(await second.close(), isFalse);
      expect(await second.close(abandonUnsaved: true), isTrue);
    },
  );

  test('failure before commit permits explicit retry only', () async {
    final session = await h.editing();
    h.controlled.writeError = StateError('disk');
    session.edit(_buffer('pending'));
    expect(await session.flush(), LocalRichTextFlushResult.failed);
    expect(await h.inner.loadRichTextBuffer(_key), isNull);
    session.edit(_buffer('latest'));
    expect(session.state.buffer!.text, 'latest');
    h.controlled.writeError = null;
    expect(session.retrySave(), isTrue);
    expect(await session.flush(), LocalRichTextFlushResult.saved);
    expect((await h.inner.loadRichTextBuffer(_key))!.buffer.text, 'latest');
  });

  test(
    'failure after commit conflicts instead of overwriting on retry',
    () async {
      final session = await h.editing();
      h.controlled.failAfterWrite = true;
      session.edit(_buffer('committed'));
      expect(await session.flush(), LocalRichTextFlushResult.failed);
      expect(
        (await h.inner.loadRichTextBuffer(_key))!.buffer.text,
        'committed',
      );
      h.controlled.failAfterWrite = false;
      expect(session.retrySave(), isTrue);
      expect(await session.flush(), LocalRichTextFlushResult.conflict);
      expect(await session.close(), isFalse);
    },
  );

  test('ambiguous apply cannot retry against stale token', () async {
    final session = await h.editing();
    session.edit(_buffer('applied'));
    await session.flush();
    h.controlled.failAfterFinish = true;
    expect(
      await session.apply(confirmed: true),
      LocalRichTextFinishResult.failed,
    );
    expect(session.state.hasUnsavedChanges, isTrue);
    h.controlled.failAfterFinish = false;
    expect(
      await session.apply(confirmed: true),
      LocalRichTextFinishResult.conflict,
    );
    expect((await h.inner.load(_key))!.body.blocks[0]['text'], 'applied');
  });

  test(
    'identity invalidation clears state while captured writes finish',
    () async {
      final session = await h.editing();
      final gate = h.controlled.writeGate = Completer<void>();
      session.edit(_buffer('first'));
      await h.controlled.writeStarted.future;
      session.edit(_buffer('last'));
      h.identity.change('other');
      expect(session.state.phase, LocalRichTextPhase.invalidated);
      expect(session.state.buffer, isNull);
      expect(session.edit(_buffer('not admitted')), isFalse);
      gate.complete();
      expect(await session.close(), isTrue);
      expect((await h.inner.loadRichTextBuffer(_key))!.buffer.text, 'last');
    },
  );

  test('delayed open cannot expose prior account', () async {
    final parent = await h.create();
    final session = h.session(parent);
    final gate = h.controlled.loadGate = Completer<void>();
    final opening = session.open();
    await h.controlled.loadStarted.future;
    h.identity.change('other');
    gate.complete();
    await opening;
    expect(session.state.phase, LocalRichTextPhase.invalidated);
    expect(session.state.body, isNull);
    expect(session.state.buffer, isNull);
  });

  test('synchronous listener invalidation cannot leak later state', () async {
    final parent = await h.create();
    final session = h.session(parent);
    final phases = <LocalRichTextPhase>[];
    final subscription = session.changes.listen((state) {
      phases.add(state.phase);
      if (state.phase == LocalRichTextPhase.recoveryChoice) {
        h.identity.change('other');
      }
    });
    await session.open();
    expect(phases.last, LocalRichTextPhase.invalidated);
    expect(session.state.buffer, isNull);
    await subscription.cancel();
  });

  test(
    'indexed resolver rereads selected snapshot and still requires choice',
    () async {
      final parent = await h.create();
      await h.inner.createRichTextBuffer(
        expected: parent,
        buffer: _buffer('restored'),
        updatedAt: _time,
      );
      final resolver = OpenIndexedRichTextRecovery(
        store: h.controlled,
        identity: h.identity,
      );
      final entry = StructuredRecoveryIndexEntry(
        rowId: parent.rowId,
        key: _key,
      );
      final result = await resolver(
        entry: entry,
        fence: _fence,
        isCurrent: () => true,
      );
      expect(result.status, IndexedRichTextRecoveryStatus.ready);
      final session = result.session!;
      h.sessions.add(session);
      await session.open();
      expect(session.state.phase, LocalRichTextPhase.recoveryChoice);
      expect(session.state.buffer!.text, 'restored');
      expect(session.state.bufferAvailable, isTrue);
      expect(session.resume(), isTrue);
    },
  );

  test('indexed resolver rejects stale row and obsolete route', () async {
    final parent = await h.create();
    await h.inner.createRichTextBuffer(
      expected: parent,
      buffer: _buffer('restored'),
      updatedAt: _time,
    );
    final resolver = OpenIndexedRichTextRecovery(
      store: h.controlled,
      identity: h.identity,
    );
    final entry = StructuredRecoveryIndexEntry(
      rowId: parent.rowId + 1,
      key: _key,
    );
    expect(
      (await resolver(
        entry: entry,
        fence: _fence,
        isCurrent: () => true,
      )).status,
      IndexedRichTextRecoveryStatus.changed,
    );
    expect(
      (await resolver(
        entry: entry,
        fence: _fence,
        isCurrent: () => false,
      )).status,
      IndexedRichTextRecoveryStatus.obsolete,
    );
  });

  test('restart recovers exact buffer after explicit re-selection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'rich-coordinator-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/db.sqlite');
    final first = _Harness(database: AppDatabase(NativeDatabase(file)));
    final parent = await first.create();
    final session = await first.editing(parent: parent);
    final value = _buffer('persist', base: 7, extent: 2, start: 2, end: 4);
    session.edit(value);
    expect(await session.flush(), LocalRichTextFlushResult.saved);
    await first.dispose();
    final reopened = _Harness(database: AppDatabase(NativeDatabase(file)));
    addTearDown(reopened.dispose);
    final saved = (await reopened.inner.loadRichTextBuffer(_key))!;
    final recovery = reopened.session(saved.parent, saved: saved);
    await recovery.open();
    expect(recovery.state.phase, LocalRichTextPhase.recoveryChoice);
    expect(recovery.state.buffer!.encode(), value.encode());
    expect(recovery.resume(), isTrue);
    expect(
      await recovery.apply(confirmed: true),
      LocalRichTextFinishResult.invalid,
    );
  });
}
