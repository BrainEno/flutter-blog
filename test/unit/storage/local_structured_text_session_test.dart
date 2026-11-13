import 'dart:async';
import 'dart:io';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';
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

StructuredTextBuffer _buffer(String text) =>
    StructuredTextBuffer(blockId: 'paragraph', text: text);

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
class _ControlledStore implements StructuredTextSessionStore {
  _ControlledStore(this.inner);
  final StructuredTextSessionStore inner;
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
  int loads = 0;
  int creates = 0;
  int replacements = 0;
  int applies = 0;
  int discards = 0;
  void Function()? onWrite;

  @override
  Future<StructuredTextBufferRecovery?> loadTextBuffer(
    StructuredBodyKey key,
  ) async {
    loads++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    if (loadGate case final gate?) await gate.future;
    if (loadError case final error?) throw error;
    return inner.loadTextBuffer(key);
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
  Future<StructuredTextBufferRecovery?> createTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    creates++;
    await _beforeWrite();
    final result = await inner.createTextBuffer(
      expected: expected,
      buffer: buffer,
      updatedAt: updatedAt,
    );
    if (failAfterWrite) throw StateError('ambiguous commit');
    return result;
  }

  @override
  Future<StructuredTextBufferRecovery?> replaceTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    replacements++;
    await _beforeWrite();
    final result = await inner.replaceTextBuffer(
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
  Future<StructuredBodyRecovery?> applyTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    applies++;
    await _beforeFinish();
    return inner.applyTextBuffer(expected: expected, updatedAt: updatedAt);
  }

  @override
  Future<StructuredBodyRecovery?> discardTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    discards++;
    await _beforeFinish();
    return inner.discardTextBuffer(expected: expected, updatedAt: updatedAt);
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
  final sessions = <LocalStructuredTextSession>[];

  Future<StructuredBodyRecovery> create({StructuredBodyKey? key}) async =>
      (await inner.create(
        key: key ?? _key,
        base: _body(),
        body: _body(),
        updatedAt: _time,
      ))!;

  LocalStructuredTextSession session(
    StructuredBodyRecovery parent, {
    String block = 'paragraph',
    StructuredBodyKey? key,
    NowaveSessionFence fence = _fence,
    StructuredTextSessionStore? store,
  }) {
    final result = LocalStructuredTextSession(
      key: key ?? _key,
      selectedRowId: parent.rowId,
      blockId: block,
      fence: fence,
      identity: identity,
      store: store ?? controlled,
      now: () => _time,
    );
    sessions.add(result);
    return result;
  }

  Future<LocalStructuredTextSession> editing({
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
  group('explicit local recovery and target safety', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test(
      'initial state requires a selected row and explicit recovery',
      () async {
        final parent = await h.create();
        final session = h.session(parent);
        expect(session.state.phase, LocalTextPhase.initial);
        expect(session.edit('premature'), isFalse);
        await session.open();
        expect(session.state.phase, LocalTextPhase.recoveryChoice);
        expect(session.state.text, 'literal **asterisks**');
        expect(session.state.body!.toJsonBlocks(), parent.body.toJsonBlocks());
        expect(session.state.bufferAvailable, isFalse);
        expect(session.edit('before consent'), isFalse);
        expect(session.resume(), isTrue);
        expect(session.state.phase, LocalTextPhase.editing);
        expect(await session.flush(), LocalTextFlushResult.saved);
        expect(await h.inner.loadTextBuffer(_key), isNull);
      },
    );

    test(
      'saved empty input requires recovery and cancel does not delete it',
      () async {
        final parent = await h.create();
        final saved = (await h.inner.createTextBuffer(
          expected: parent,
          buffer: _buffer(''),
          updatedAt: _time,
        ))!;
        final session = h.session(parent);
        await session.open();
        expect(session.state.phase, LocalTextPhase.recoveryChoice);
        expect(session.state.bufferAvailable, isTrue);
        expect(session.state.text, '');
        expect(session.cancel(), isTrue);
        expect(session.state.phase, LocalTextPhase.cancelled);
        expect(session.state.text, isNull);
        expect(session.resume(), isFalse);
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          saved.storageJson,
        );
      },
    );

    test('a changed row incarnation cannot be silently selected', () async {
      final parent = await h.create();
      expect(await h.inner.discard(parent), isTrue);
      final replacement = await h.create();
      expect(replacement.rowId, isNot(parent.rowId));
      final session = h.session(parent);
      await session.open();
      expect(session.state.phase, LocalTextPhase.conflict);
      expect(session.state.body, isNull);
      expect(session.resume(), isFalse);
      expect((await h.inner.load(_key))!.rowId, replacement.rowId);
    });

    test('missing row never falls back to a remote or blank article', () async {
      final parent = await h.create();
      expect(await h.inner.discard(parent), isTrue);
      final session = h.session(parent);
      await session.open();
      expect(session.state.phase, LocalTextPhase.conflict);
      expect(session.state.body, isNull);
    });

    test('formatted, non-text and absent block targets are refused', () async {
      final parent = await h.create();
      for (final block in [
        'heading',
        'quote',
        'list',
        'image-one',
        'code',
        'missing',
      ]) {
        final session = h.session(parent, block: block);
        await session.open();
        expect(session.state.phase, LocalTextPhase.loadFailed, reason: block);
        expect(session.state.text, isNull);
        expect(session.resume(), isFalse);
      }
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        parent.body.toJsonBlocks(),
      );
    });

    test(
      'another block buffer causes conflict and is not overwritten',
      () async {
        final body = StructuredArticleDraft.parse(
          version: 1,
          blocks: [
            {'id': 'first', 'type': 'paragraph', 'text': 'first'},
            {'id': 'second', 'type': 'paragraph', 'text': 'second'},
          ],
        );
        final parent = (await h.inner.create(
          key: _key,
          base: body,
          body: body,
          updatedAt: _time,
        ))!;
        final saved = (await h.inner.createTextBuffer(
          expected: parent,
          buffer: StructuredTextBuffer(blockId: 'second', text: 'preserve'),
          updatedAt: _time,
        ))!;
        final session = h.session(parent, block: 'first');
        await session.open();
        expect(session.state.phase, LocalTextPhase.conflict);
        expect(session.state.bufferAvailable, isTrue);
        expect(session.state.text, isNull);
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          saved.storageJson,
        );
      },
    );

    test(
      'corrupt or unknown data blocks local opening without deletion',
      () async {
        final parent = await h.create();
        await h.db.customStatement(
          "UPDATE structured_body_drafts SET text_buffer = '{bad'",
        );
        final session = h.session(parent);
        await session.open();
        expect(session.state.phase, LocalTextPhase.loadFailed);
        expect(session.state.body, isNull);
        expect(
          await h.db
              .customSelect('SELECT text_buffer FROM structured_body_drafts')
              .getSingle()
              .then((row) => row.read<String>('text_buffer')),
          '{bad',
        );
      },
    );

    test(
      'buffer created between reads blocks opening without losing it',
      () async {
        final parent = await h.create();
        final gate = h.controlled.parentLoadGate = Completer<void>();
        final session = h.session(parent);
        final opening = session.open();
        await h.controlled.parentLoadStarted.future;
        final saved = (await h.inner.createTextBuffer(
          expected: parent,
          buffer: _buffer('concurrent'),
          updatedAt: _time,
        ))!;
        gate.complete();
        await opening;
        expect(session.state.phase, LocalTextPhase.loadFailed);
        expect(session.state.text, isNull);
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          saved.storageJson,
        );
      },
    );

    test('backend and locale namespace cannot select another row', () async {
      final parent = await h.create();
      final otherLocale = StructuredBodyKey(
        userId: 'author',
        articleId: 'article-id',
        locale: 'zh-TW',
      );
      final wrongLocale = h.session(parent, key: otherLocale);
      await wrongLocale.open();
      expect(wrongLocale.state.phase, LocalTextPhase.conflict);
      final otherStore = SqliteStructuredBodyRecoveryStore(
        h.db,
        apiBaseUrl: Uri.parse('https://other.invalid/v1'),
      );
      final wrongBackend = h.session(parent, store: otherStore);
      await wrongBackend.open();
      expect(wrongBackend.state.phase, LocalTextPhase.conflict);
      expect((await h.inner.load(_key))!.rowId, parent.rowId);
    });

    test('read failure is distinct and does not make writes', () async {
      final parent = await h.create();
      h.controlled.loadError = StateError('offline storage');
      final session = h.session(parent);
      await session.open();
      expect(session.state.phase, LocalTextPhase.loadFailed);
      expect(session.edit('x'), isFalse);
      expect(h.controlled.creates, 0);
      expect((await h.inner.load(_key))!.revision, parent.revision);
    });
  });

  group('ordered durable input', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test(
      'rapid edits coalesce behind an in-flight write without losing the last value',
      () async {
        final session = await h.editing();
        final gate = h.controlled.writeGate = Completer<void>();
        expect(session.edit('first'), isTrue);
        await h.controlled.writeStarted.future;
        expect(session.edit('second'), isTrue);
        expect(session.edit(''), isTrue);
        expect(session.edit('final 🦋'), isTrue);
        expect(session.state.text, 'final 🦋');
        expect(session.state.saving, isTrue);
        gate.complete();
        expect(await session.flush(), LocalTextFlushResult.saved);
        expect(session.state.hasUnsavedChanges, isFalse);
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'final 🦋');
        expect(h.controlled.creates, 1);
        expect(h.controlled.replacements, 1);
      },
    );

    test('oversize input is rejected before changing the prior text', () async {
      final session = await h.editing();
      expect(session.edit('safe'), isTrue);
      expect(await session.flush(), LocalTextFlushResult.saved);
      expect(() => session.edit('x' * 20001), throwsFormatException);
      expect(session.state.text, 'safe');
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'safe');
    });

    test(
      'storage failure preserves newest pending input for explicit retry',
      () async {
        final session = await h.editing();
        final gate = h.controlled.writeGate = Completer<void>();
        h.controlled.writeError = StateError('disk error');
        session.edit('first');
        await h.controlled.writeStarted.future;
        session.edit('newest');
        gate.complete();
        expect(await session.flush(), LocalTextFlushResult.failed);
        expect(session.state.phase, LocalTextPhase.saveFailed);
        expect(session.state.text, 'newest');
        expect(session.state.hasUnsavedChanges, isTrue);
        expect(await session.close(), isFalse);
        h.controlled.writeError = null;
        expect(session.retrySave(), isTrue);
        expect(await session.flush(), LocalTextFlushResult.saved);
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'newest');
      },
    );

    test(
      'ambiguous committed failure retries with the original CAS and stops',
      () async {
        final session = await h.editing();
        h.controlled.failAfterWrite = true;
        session.edit('committed but unacknowledged');
        expect(await session.flush(), LocalTextFlushResult.failed);
        h.controlled.failAfterWrite = false;
        expect(session.retrySave(), isTrue);
        expect(await session.flush(), LocalTextFlushResult.conflict);
        expect(session.state.text, 'committed but unacknowledged');
        expect(session.retrySave(), isFalse);
        expect(
          (await h.inner.loadTextBuffer(_key))!.buffer.text,
          'committed but unacknowledged',
        );
        expect(await session.close(), isFalse);
      },
    );

    test('competing parent edit stops the stale first buffer save', () async {
      final parent = await h.create();
      final session = await h.editing(parent: parent);
      final changed = (await h.inner.replace(
        expected: parent,
        body: parent.body.replacePlainText('paragraph', 'other editor'),
        updatedAt: _time,
      ))!;
      session.edit('local pending');
      expect(await session.flush(), LocalTextFlushResult.conflict);
      expect(session.state.text, 'local pending');
      expect(session.state.hasUnsavedChanges, isTrue);
      expect(
        (await h.inner.load(_key))!.bodyStorageJson,
        changed.bodyStorageJson,
      );
      expect(await h.inner.loadTextBuffer(_key), isNull);
    });

    test(
      'competing buffer update stops the stale writer without overwrite',
      () async {
        final parent = await h.create();
        await h.inner.createTextBuffer(
          expected: parent,
          buffer: _buffer('initial'),
          updatedAt: _time,
        );
        final session = await h.editing(parent: parent);
        final other = (await h.inner.loadTextBuffer(_key))!;
        final updated = (await h.inner.replaceTextBuffer(
          expected: other,
          buffer: _buffer('other editor'),
          updatedAt: _time,
        ))!;
        session.edit('my text');
        expect(await session.flush(), LocalTextFlushResult.conflict);
        expect(session.state.text, 'my text');
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          updated.storageJson,
        );
        expect(session.retrySave(), isFalse);
      },
    );

    test('two sessions can never both create the first buffer', () async {
      final parent = await h.create();
      final first = await h.editing(parent: parent);
      final second = await h.editing(parent: parent);
      first.edit('first');
      second.edit('second');
      final outcomes = await Future.wait([first.flush(), second.flush()]);
      expect(
        outcomes.where((value) => value == LocalTextFlushResult.saved),
        hasLength(1),
      );
      expect(
        outcomes.where((value) => value == LocalTextFlushResult.conflict),
        hasLength(1),
      );
      expect([
        'first',
        'second',
      ], contains((await h.inner.loadTextBuffer(_key))!.buffer.text));
    });
  });

  group('explicit apply and discard', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('unconfirmed actions do not write', () async {
      final session = await h.editing();
      session.edit('pending');
      expect(await session.flush(), LocalTextFlushResult.saved);
      expect(
        await session.apply(confirmed: false),
        LocalTextFinishResult.notReady,
      );
      expect(
        await session.discard(confirmed: false),
        LocalTextFinishResult.notReady,
      );
      expect(h.controlled.applies, 0);
      expect(h.controlled.discards, 0);
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'pending');
    });

    test(
      'apply waits for rapid writes and preserves all other block data',
      () async {
        final parent = await h.create();
        final session = await h.editing(parent: parent);
        final gate = h.controlled.writeGate = Completer<void>();
        session.edit('first');
        await h.controlled.writeStarted.future;
        session.edit('latest');
        final result = session.apply(confirmed: true);
        expect(session.state.finishing, isTrue);
        expect(session.edit('too late'), isFalse);
        gate.complete();
        expect(await result, LocalTextFinishResult.finished);
        expect(session.state.phase, LocalTextPhase.finished);
        expect(session.state.body!.blocks[2]['text'], 'latest');
        expect(session.state.body!.blocks[0], parent.body.blocks[0]);
        expect(session.state.body!.blocks[1], parent.body.blocks[1]);
        expect(await h.inner.loadTextBuffer(_key), isNull);
        final restored = (await h.inner.load(_key))!;
        expect(
          restored.body.toJsonBlocks(),
          session.state.body!.toJsonBlocks(),
        );
        expect(restored.baseStorageJson, parent.baseStorageJson);
      },
    );

    test('empty input remains recoverable when apply is invalid', () async {
      final session = await h.editing();
      session.edit('');
      expect(
        await session.apply(confirmed: true),
        LocalTextFinishResult.invalid,
      );
      expect(session.state.phase, LocalTextPhase.editing);
      expect(session.state.finishing, isFalse);
      expect(session.state.text, '');
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, '');
      expect(h.controlled.applies, 0);
      session.edit('valid now');
      expect(
        await session.apply(confirmed: true),
        LocalTextFinishResult.finished,
      );
    });

    test(
      'discard removes only the buffer and leaves base and body exact',
      () async {
        final parent = await h.create();
        final session = await h.editing(parent: parent);
        session.edit('');
        expect(
          await session.discard(confirmed: true),
          LocalTextFinishResult.finished,
        );
        expect(session.state.body!.toJsonBlocks(), parent.body.toJsonBlocks());
        expect(await h.inner.loadTextBuffer(_key), isNull);
        final restored = (await h.inner.load(_key))!;
        expect(restored.bodyStorageJson, parent.bodyStorageJson);
        expect(restored.baseStorageJson, parent.baseStorageJson);
        expect(restored.revision, greaterThan(parent.revision));
      },
    );

    test('discard with no buffer leaves the parent untouched', () async {
      final parent = await h.create();
      final session = await h.editing(parent: parent);
      expect(
        await session.discard(confirmed: true),
        LocalTextFinishResult.finished,
      );
      expect(h.controlled.discards, 0);
      expect((await h.inner.load(_key))!.revision, parent.revision);
    });

    test(
      'failed action can be retried without dropping persisted input',
      () async {
        final session = await h.editing();
        session.edit('saved');
        expect(await session.flush(), LocalTextFlushResult.saved);
        h.controlled.finishError = StateError('storage failed');
        expect(
          await session.apply(confirmed: true),
          LocalTextFinishResult.failed,
        );
        expect(session.state.phase, LocalTextPhase.actionFailed);
        expect(session.state.text, 'saved');
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'saved');
        h.controlled.finishError = null;
        expect(
          await session.apply(confirmed: true),
          LocalTextFinishResult.finished,
        );
        expect((await h.inner.load(_key))!.body.blocks[2]['text'], 'saved');
      },
    );

    test(
      'editing after a failed action can establish durability again',
      () async {
        final session = await h.editing();
        session.edit('first');
        await session.flush();
        h.controlled.finishError = StateError('failed');
        expect(
          await session.apply(confirmed: true),
          LocalTextFinishResult.failed,
        );
        expect(await session.close(), isFalse);
        h.controlled.finishError = null;
        expect(session.edit('new durable input'), isTrue);
        expect(await session.flush(), LocalTextFlushResult.saved);
        expect(
          (await h.inner.loadTextBuffer(_key))!.buffer.text,
          'new durable input',
        );
        expect(await session.close(), isTrue);
      },
    );

    test('stale discard fails without deleting a competing buffer', () async {
      final session = await h.editing();
      session.edit('mine');
      expect(await session.flush(), LocalTextFlushResult.saved);
      final previous = (await h.inner.loadTextBuffer(_key))!;
      await h.inner.replaceTextBuffer(
        expected: previous,
        buffer: _buffer('theirs'),
        updatedAt: _time,
      );
      expect(
        await session.discard(confirmed: true),
        LocalTextFinishResult.conflict,
      );
      expect(session.state.phase, LocalTextPhase.conflict);
      expect(session.state.hasUnsavedChanges, isTrue);
      expect(await session.close(), isFalse);
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'theirs');
    });

    test(
      'stale apply fails without modifying the body or other buffer',
      () async {
        final session = await h.editing();
        session.edit('mine');
        await session.flush();
        final previous = (await h.inner.loadTextBuffer(_key))!;
        await h.inner.replaceTextBuffer(
          expected: previous,
          buffer: _buffer('theirs'),
          updatedAt: _time,
        );
        expect(
          await session.apply(confirmed: true),
          LocalTextFinishResult.conflict,
        );
        final current = (await h.inner.loadTextBuffer(_key))!;
        expect(current.buffer.text, 'theirs');
        expect(current.parent.body.blocks[2]['text'], 'literal **asterisks**');
      },
    );
  });

  group('identity, lifecycle and restart', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('wrong account or generation never loads private state', () async {
      final parent = await h.create();
      final wrong = h.session(
        parent,
        fence: const NowaveSessionFence(userId: 'other', generation: 1),
      );
      await wrong.open();
      expect(wrong.state.phase, LocalTextPhase.invalidated);
      expect(h.controlled.loads, 0);
      final old = h.session(
        parent,
        fence: const NowaveSessionFence(userId: 'author', generation: 0),
      );
      await old.open();
      expect(old.state.phase, LocalTextPhase.invalidated);
      expect(h.controlled.loads, 0);
    });

    test(
      'identity changes during a delayed read never expose its result',
      () async {
        final parent = await h.create();
        final gate = h.controlled.loadGate = Completer<void>();
        final session = h.session(parent);
        final opening = session.open();
        await h.controlled.loadStarted.future;
        h.identity.change('someone-else');
        expect(session.state.phase, LocalTextPhase.invalidated);
        expect(session.state.body, isNull);
        gate.complete();
        await opening;
        expect(session.state.phase, LocalTextPhase.invalidated);
        expect(session.state.text, isNull);
        expect(session.resume(), isFalse);
      },
    );

    test(
      'admitted writes finish only for the old account after identity changes',
      () async {
        final session = await h.editing();
        final gate = h.controlled.writeGate = Completer<void>();
        session.edit('first');
        await h.controlled.writeStarted.future;
        session.edit('latest');
        h.identity.change('other');
        expect(session.state.phase, LocalTextPhase.invalidated);
        expect(session.state.body, isNull);
        expect(session.state.text, isNull);
        expect(session.edit('not admitted'), isFalse);
        gate.complete();
        expect(await session.close(), isTrue);
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'latest');
        expect(
          await h.inner.loadTextBuffer(
            StructuredBodyKey(
              userId: 'other',
              articleId: 'article-id',
              locale: 'en',
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'failed admitted write remains unsaved after identity changes',
      () async {
        final session = await h.editing();
        final gate = h.controlled.writeGate = Completer<void>();
        h.controlled.writeError = StateError('failure');
        session.edit('must not silently vanish');
        await h.controlled.writeStarted.future;
        h.identity.change(null);
        gate.complete();
        expect(await session.close(), isFalse);
        expect(session.state.phase, LocalTextPhase.invalidated);
        expect(session.state.text, isNull);
        expect(await session.close(abandonUnsaved: true), isTrue);
      },
    );

    test(
      'close waits for the active writer without deleting recovery',
      () async {
        final session = await h.editing();
        final gate = h.controlled.writeGate = Completer<void>();
        session.edit('durable');
        await h.controlled.writeStarted.future;
        var closed = false;
        final close = session.close().then((value) {
          closed = true;
          return value;
        });
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        expect(session.edit('late'), isFalse);
        gate.complete();
        expect(await close, isTrue);
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'durable');
      },
    );

    test(
      'close waits for a delayed open and never exposes its late result',
      () async {
        final parent = await h.create();
        final gate = h.controlled.loadGate = Completer<void>();
        final session = h.session(parent);
        final opening = session.open();
        await h.controlled.loadStarted.future;
        final closing = session.close();
        gate.complete();
        await opening;
        expect(await closing, isTrue);
        expect(session.state.phase, LocalTextPhase.closed);
        expect(session.state.text, isNull);
      },
    );

    test(
      'account change during apply does not expose the completed body',
      () async {
        final session = await h.editing();
        session.edit('captured');
        await session.flush();
        final gate = h.controlled.finishGate = Completer<void>();
        final applying = session.apply(confirmed: true);
        await h.controlled.finishStarted.future;
        h.identity.change('other');
        gate.complete();
        expect(await applying, LocalTextFinishResult.obsolete);
        expect(session.state.phase, LocalTextPhase.invalidated);
        expect(session.state.body, isNull);
        expect((await h.inner.load(_key))!.body.blocks[2]['text'], 'captured');
      },
    );

    test('close waits for an already admitted apply action', () async {
      final session = await h.editing();
      session.edit('to apply');
      await session.flush();
      final gate = h.controlled.finishGate = Completer<void>();
      final applying = session.apply(confirmed: true);
      await h.controlled.finishStarted.future;
      var closed = false;
      final closing = session.close().then((value) {
        closed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      gate.complete();
      expect(await applying, LocalTextFinishResult.finished);
      expect(await closing, isTrue);
      expect((await h.inner.load(_key))!.body.blocks[2]['text'], 'to apply');
    });

    test(
      'synchronous observer switching account cannot leak a later state',
      () async {
        final parent = await h.create();
        final session = h.session(parent);
        final phases = <LocalTextPhase>[];
        final subscription = session.changes.listen((state) {
          phases.add(state.phase);
          if (state.phase == LocalTextPhase.recoveryChoice)
            h.identity.change('other');
        });
        await session.open();
        expect(session.state.phase, LocalTextPhase.invalidated);
        expect(phases.last, LocalTextPhase.invalidated);
        expect(session.state.text, isNull);
        await subscription.cancel();
      },
    );

    test(
      'restart restores an empty buffer only after explicit choice',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'text-coordinator-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/db.sqlite');
        final first = _Harness(database: AppDatabase(NativeDatabase(file)));
        final parent = await first.create();
        final editing = await first.editing(parent: parent);
        editing.edit('');
        expect(await editing.flush(), LocalTextFlushResult.saved);
        await first.dispose();
        final reopened = _Harness(database: AppDatabase(NativeDatabase(file)));
        addTearDown(reopened.dispose);
        final recovery = reopened.session(parent);
        await recovery.open();
        expect(recovery.state.phase, LocalTextPhase.recoveryChoice);
        expect(recovery.state.text, '');
        expect(recovery.state.bufferAvailable, isTrue);
        expect(recovery.resume(), isTrue);
        expect(
          await recovery.apply(confirmed: true),
          LocalTextFinishResult.invalid,
        );
        expect((await reopened.inner.loadTextBuffer(_key))!.buffer.text, '');
      },
    );
  });
}
