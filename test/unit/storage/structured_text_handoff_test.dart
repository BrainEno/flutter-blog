import 'dart:async';
import 'dart:io';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/local_structured_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';
import 'package:belog/features/blog/domain/usecase/open_indexed_recovery.dart';
import 'package:belog/features/blog/domain/usecase/open_indexed_text_recovery.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'stable-id',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _date = DateTime.utc(2026, 10, 29);
final _backend = Uri.parse('https://one.example.invalid/v1');

StructuredArticleDraft _body() {
  final fixture = structuredArticle();
  return StructuredArticleDraft.parse(
    version: fixture['contentBlocksVersion'],
    blocks: fixture['contentBlocks'],
  );
}

StructuredSessionMetadata _metadata(String title) => StructuredSessionMetadata(
  slug: 'original-slug',
  title: title,
  summary: '',
  workType: 'essay',
  publicationState: 'draft',
  tags: StructuredTaxonomySelection(values: ['one'], touched: true),
  categories: StructuredTaxonomySelection(values: ['category'], touched: false),
  cover: StructuredCoverSelection.local(
    mimeType: 'image/png',
    bytes: [0, 1, 255],
  ),
);

StructuredEditionReadResult _remote() => StructuredEditionReadResult.found(
  StructuredEdition(
    key: _key,
    body: _body(),
    metadata: _metadata('original'),
    rawArticle: {'id': 'stable-id'},
    metadataIssues: const {},
  ),
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
    accessToken = user == null ? null : 'token';
    sessionGeneration++;
    events.add(null);
  }
}

class _Reader implements StructuredEditionReader {
  StructuredEditionReadResult result = _remote();
  int calls = 0;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async {
    calls++;
    return result;
  }
}

class _ControlledStore implements StructuredTextSessionStore {
  _ControlledStore(this.inner);
  final SqliteStructuredBodyRecoveryStore inner;
  Completer<void>? writeGate;
  Completer<void>? bufferLoadGate;
  final bufferLoadStarted = Completer<void>();
  final writeStarted = Completer<void>();
  Object? writeError;
  bool failAfterCommit = false;
  int creates = 0;
  int replaces = 0;
  int bufferCreates = 0;
  void Function()? onWrite;

  Future<void> _beforeWrite() async {
    onWrite?.call();
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate case final gate?) await gate.future;
    if (writeError case final error?) throw error;
  }

  StructuredBodyRecovery? _afterWrite(StructuredBodyRecovery? result) {
    if (failAfterCommit) throw StateError('ambiguous body write');
    return result;
  }

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) =>
      inner.load(key);
  @override
  Future<StructuredBodyRecovery?> create({
    required StructuredBodyKey key,
    required StructuredArticleDraft base,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? sessionMetadata,
  }) async {
    creates++;
    await _beforeWrite();
    return _afterWrite(
      await inner.create(
        key: key,
        base: base,
        body: body,
        updatedAt: updatedAt,
        baseMetadata: baseMetadata,
        sessionMetadata: sessionMetadata,
      ),
    );
  }

  @override
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  }) async {
    replaces++;
    await _beforeWrite();
    return _afterWrite(
      await inner.replace(expected: expected, body: body, updatedAt: updatedAt),
    );
  }

  @override
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  }) async {
    replaces++;
    await _beforeWrite();
    return _afterWrite(
      await inner.replaceSession(
        expected: expected,
        body: body,
        sessionMetadata: sessionMetadata,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<bool> discard(StructuredBodyRecovery expected) =>
      inner.discard(expected);
  @override
  Future<StructuredTextBufferRecovery?> loadTextBuffer(
    StructuredBodyKey key,
  ) async {
    if (!bufferLoadStarted.isCompleted) bufferLoadStarted.complete();
    if (bufferLoadGate case final gate?) await gate.future;
    return inner.loadTextBuffer(key);
  }

  @override
  Future<StructuredTextBufferRecovery?> createTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) {
    bufferCreates++;
    return inner.createTextBuffer(
      expected: expected,
      buffer: buffer,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<StructuredTextBufferRecovery?> replaceTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) => inner.replaceTextBuffer(
    expected: expected,
    buffer: buffer,
    updatedAt: updatedAt,
  );
  @override
  Future<StructuredBodyRecovery?> applyTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => inner.applyTextBuffer(expected: expected, updatedAt: updatedAt);
  @override
  Future<StructuredBodyRecovery?> discardTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) => inner.discardTextBuffer(expected: expected, updatedAt: updatedAt);
}

/// Simulates a legacy implementation that has no combined buffer capability.
class _BodyOnlyStore implements StructuredBodyRecoveryStore {
  _BodyOnlyStore(this.inner);
  final StructuredBodyRecoveryStore inner;
  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) =>
      inner.load(key);
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
    store = _ControlledStore(inner);
    identity = _Identity();
    reader = _Reader();
    opener = OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    );
  }
  late final AppDatabase db;
  late final SqliteStructuredBodyRecoveryStore inner;
  late final _ControlledStore store;
  late final _Identity identity;
  late final _Reader reader;
  late final OpenStructuredEditingSession opener;
  final bodies = <LocalStructuredSession>[];
  final texts = <LocalStructuredTextSession>[];

  LocalStructuredSession body({OpenStructuredEditingSession? opener}) {
    final value = LocalStructuredSession(
      key: _key,
      fence: _fence,
      opener: opener ?? this.opener,
      now: () => _date,
    );
    bodies.add(value);
    return value;
  }

  Future<LocalStructuredSession> editing({
    OpenStructuredEditingSession? opener,
  }) async {
    final value = body(opener: opener);
    await value.open();
    if (value.state.phase == LocalStructuredPhase.recoveryChoice) {
      expect(value.resumeRecovery(), isTrue);
    }
    return value;
  }

  Future<StructuredBodyRecovery> seed() async => (await inner.create(
    key: _key,
    base: _body(),
    body: _body().replacePlainText('paragraph', 'local'),
    updatedAt: _date,
    baseMetadata: _metadata('original'),
    sessionMetadata: _metadata('edited'),
  ))!;
  Future<LocalStructuredTextSession> handoff(
    LocalStructuredSession body,
  ) async {
    final result = await body.handoffPlainText('paragraph');
    expect(result.status, LocalTextHandoffStatus.ready);
    final text = result.session!;
    texts.add(text);
    return text;
  }

  Future<void> dispose() async {
    for (final text in texts) {
      await text.close(abandonUnsaved: true);
    }
    for (final body in bodies) {
      await body.close(abandonUnsaved: true);
    }
    await identity.events.close();
    await db.close();
  }
}

void main() {
  group('controlled transition from the body editor', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('an untouched remote body is saved locally before handoff', () async {
      final body = await h.editing();
      expect(await h.inner.load(_key), isNull);
      final text = await h.handoff(body);
      expect(body.state.phase, LocalStructuredPhase.closed);
      expect(body.edit((draft) => draft.remove('code')), isFalse);
      final saved = (await h.inner.load(_key))!;
      expect(saved.revision, 1);
      expect(saved.body.toJsonBlocks(), _body().toJsonBlocks());
      expect(saved.base.toJsonBlocks(), _body().toJsonBlocks());
      expect(saved.sessionMetadata!.toJson(), _metadata('original').toJson());
      expect(await h.inner.loadTextBuffer(_key), isNull);
      expect(h.store.creates, 1);
      expect(h.store.bufferCreates, 0);
      await text.open();
      expect(text.state.phase, LocalTextPhase.recoveryChoice);
      expect(text.state.text, 'literal **asterisks**');
      expect(text.edit('not yet'), isFalse);
      expect(text.resume(), isTrue);
    });

    test(
      'existing clean recovery is handed off without an extra write',
      () async {
        final initial = await h.seed();
        final body = await h.editing();
        final text = await h.handoff(body);
        final current = (await h.inner.load(_key))!;
        expect(current.revision, initial.revision);
        expect(current.rowId, initial.rowId);
        expect(h.store.creates, 0);
        expect(h.store.replaces, 0);
        await text.open();
        expect(text.state.text, 'local');
        expect(text.state.phase, LocalTextPhase.recoveryChoice);
      },
    );

    test(
      'already saved local body and metadata are handed off intact',
      () async {
        final body = await h.editing();
        body.edit(
          (value) => value.replacePlainText('paragraph', 'edited local'),
        );
        body.editMetadata(_metadata('changed title'));
        expect(await body.flush(), LocalStructuredFlushResult.saved);
        final before = (await h.inner.load(_key))!;
        final text = await h.handoff(body);
        await text.open();
        expect(text.state.text, 'edited local');
        expect(
          (await h.inner.load(_key))!.sessionMetadata!.toJson(),
          _metadata('changed title').toJson(),
        );
        expect((await h.inner.load(_key))!.revision, before.revision);
      },
    );

    test(
      'handoff waits for rapid in-flight body edits and freezes new edits',
      () async {
        final body = await h.editing();
        final gate = h.store.writeGate = Completer<void>();
        body.edit((value) => value.replacePlainText('paragraph', 'first'));
        await h.store.writeStarted.future;
        body.edit((value) => value.replacePlainText('paragraph', 'latest'));
        body.editMetadata(_metadata('latest metadata'));
        final transfer = body.handoffPlainText('paragraph');
        expect(
          body.edit((value) => value.replacePlainText('paragraph', 'too late')),
          isFalse,
        );
        expect(body.editMetadata(_metadata('too late')), isFalse);
        expect(
          (await body.handoffPlainText('paragraph')).status,
          LocalTextHandoffStatus.notReady,
        );
        gate.complete();
        final result = await transfer;
        expect(result.status, LocalTextHandoffStatus.ready);
        final text = result.session!;
        h.texts.add(text);
        await text.open();
        expect(text.state.text, 'latest');
        expect(
          (await h.inner.load(_key))!.sessionMetadata!.title,
          'latest metadata',
        );
        expect(h.store.creates, 1);
        expect(h.store.replaces, 1);
      },
    );

    test(
      'synchronous observers cannot edit while handoff starts saving',
      () async {
        final body = await h.editing();
        final attempts = <bool>[];
        final subscription = body.changes.listen((state) {
          if (state.saving) {
            attempts.add(
              body.edit(
                (value) => value.replacePlainText('paragraph', 'late observer'),
              ),
            );
          }
        });
        final text = await h.handoff(body);
        await subscription.cancel();
        expect(attempts, [false]);
        await text.open();
        expect(text.state.text, 'literal **asterisks**');
      },
    );

    test('heading and quote without inline runs are valid targets', () async {
      final value = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {'id': 'h', 'type': 'heading', 'level': 2, 'text': 'heading'},
          {
            'id': 'q',
            'type': 'quote',
            'text': 'quote',
            'attribution': 'author',
          },
        ],
      );
      h.reader.result = StructuredEditionReadResult.found(
        StructuredEdition(
          key: _key,
          body: value,
          metadata: _metadata('title'),
          rawArticle: {'id': 'stable-id'},
          metadataIssues: const {},
        ),
      );
      final body = await h.editing();
      final result = await body.handoffPlainText('q');
      expect(result.status, LocalTextHandoffStatus.ready);
      final text = result.session!;
      h.texts.add(text);
      await text.open();
      expect(text.state.text, 'quote');
      expect(text.resume(), isTrue);
      text.edit('new quote');
      expect(await text.apply(confirmed: true), LocalTextFinishResult.finished);
      final saved = (await h.inner.load(_key))!;
      expect(saved.body.blocks[0], value.blocks[0]);
      expect(saved.body.blocks[1]['attribution'], 'author');
      expect(saved.body.blocks[1]['text'], 'new quote');
    });

    test('invalid targets do not save or close the original editor', () async {
      final body = await h.editing();
      for (final block in [
        '',
        'missing',
        'heading',
        'quote',
        'image-one',
        'list',
        'code',
      ]) {
        final result = await body.handoffPlainText(block);
        expect(
          result.status,
          LocalTextHandoffStatus.invalidTarget,
          reason: block,
        );
        expect(result.session, isNull);
        expect(body.state.phase, LocalStructuredPhase.editing);
      }
      expect(await h.inner.load(_key), isNull);
      expect(h.store.creates, 0);
      expect(
        body.edit(
          (value) => value.replacePlainText('paragraph', 'still editable'),
        ),
        isTrue,
      );
      expect(await body.flush(), LocalStructuredFlushResult.saved);
    });

    test(
      'body-only store is refused rather than using another backend',
      () async {
        final opener = OpenStructuredEditingSession(
          reader: h.reader,
          store: _BodyOnlyStore(h.inner),
          identity: h.identity,
        );
        final body = await h.editing(opener: opener);
        final result = await body.handoffPlainText('paragraph');
        expect(result.status, LocalTextHandoffStatus.unsupportedStore);
        expect(result.session, isNull);
        expect(body.state.phase, LocalStructuredPhase.editing);
        expect(await h.inner.load(_key), isNull);
      },
    );

    test('recovery choice cannot be bypassed by handoff', () async {
      final before = await h.seed();
      final body = h.body();
      await body.open();
      expect(body.state.phase, LocalStructuredPhase.recoveryChoice);
      final result = await body.handoffPlainText('paragraph');
      expect(result.status, LocalTextHandoffStatus.notReady);
      expect(body.state.phase, LocalStructuredPhase.recoveryChoice);
      expect((await h.inner.load(_key))!.revision, before.revision);
    });

    test('text can be canceled without changing the just-saved body', () async {
      final body = await h.editing();
      final text = await h.handoff(body);
      final before = (await h.inner.load(_key))!;
      await text.open();
      expect(text.cancel(), isTrue);
      expect(await h.inner.loadTextBuffer(_key), isNull);
      final after = (await h.inner.load(_key))!;
      expect(after.revision, before.revision);
      expect(after.bodyStorageJson, before.bodyStorageJson);
    });
  });

  group('failure and cancellation during handoff', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test(
      'first save failure leaves the original session available to retry',
      () async {
        final body = await h.editing();
        h.store.writeError = StateError('disk unavailable');
        final result = await body.handoffPlainText('paragraph');
        expect(result.status, LocalTextHandoffStatus.failed);
        expect(result.session, isNull);
        expect(body.state.phase, LocalStructuredPhase.saveFailed);
        expect(body.state.hasUnsavedChanges, isTrue);
        expect(await body.close(), isFalse);
        expect(await h.inner.load(_key), isNull);
        h.store.writeError = null;
        expect(body.retrySave(), isTrue);
        expect(await body.flush(), LocalStructuredFlushResult.saved);
        final text = await h.handoff(body);
        await text.open();
        expect(text.state.phase, LocalTextPhase.recoveryChoice);
      },
    );

    test(
      'ambiguous parent commit cannot be blindly retried or handed off',
      () async {
        final body = await h.editing();
        h.store.failAfterCommit = true;
        expect(
          (await body.handoffPlainText('paragraph')).status,
          LocalTextHandoffStatus.failed,
        );
        expect(body.state.phase, LocalStructuredPhase.saveFailed);
        expect(
          (await h.inner.load(_key))!.body.toJsonBlocks(),
          _body().toJsonBlocks(),
        );
        h.store.failAfterCommit = false;
        expect(body.retrySave(), isTrue);
        expect(await body.flush(), LocalStructuredFlushResult.conflict);
        expect(
          (await body.handoffPlainText('paragraph')).status,
          LocalTextHandoffStatus.notReady,
        );
        expect(await body.close(), isFalse);
      },
    );

    test('another writer winning the first create produces conflict', () async {
      final body = await h.editing();
      final competitor = await h.seed();
      final result = await body.handoffPlainText('paragraph');
      expect(result.status, LocalTextHandoffStatus.conflict);
      expect(result.session, isNull);
      expect(body.state.phase, LocalStructuredPhase.conflict);
      expect(await body.close(), isFalse);
      expect(
        (await h.inner.load(_key))!.bodyStorageJson,
        competitor.bodyStorageJson,
      );
    });

    test(
      'a later body update racing a queued edit is not overwritten',
      () async {
        final parent = await h.seed();
        final body = await h.editing();
        final competing = (await h.inner.replace(
          expected: parent,
          body: parent.body.replacePlainText('paragraph', 'other editor'),
          updatedAt: _date,
        ))!;
        body.edit((value) => value.replacePlainText('paragraph', 'my edit'));
        final result = await body.handoffPlainText('paragraph');
        expect(result.status, LocalTextHandoffStatus.conflict);
        expect(body.state.body!.blocks[2]['text'], 'my edit');
        expect(
          (await h.inner.load(_key))!.bodyStorageJson,
          competing.bodyStorageJson,
        );
      },
    );

    test(
      'identity change during a save hides state and prevents a new session',
      () async {
        final body = await h.editing();
        final gate = h.store.writeGate = Completer<void>();
        final transfer = body.handoffPlainText('paragraph');
        await h.store.writeStarted.future;
        h.identity.change('other');
        expect(body.state.phase, LocalStructuredPhase.invalidated);
        expect(body.state.body, isNull);
        gate.complete();
        final result = await transfer;
        expect(result.status, LocalTextHandoffStatus.obsolete);
        expect(result.session, isNull);
        expect((await h.inner.load(_key))!.key.userId, 'author');
        expect(
          await h.inner.load(
            StructuredBodyKey(
              userId: 'other',
              articleId: 'stable-id',
              locale: 'en',
            ),
          ),
          isNull,
        );
      },
    );

    test('failed write after sign out still prevents silent close', () async {
      final body = await h.editing();
      final gate = h.store.writeGate = Completer<void>();
      h.store.writeError = StateError('storage failure');
      final transfer = body.handoffPlainText('paragraph');
      await h.store.writeStarted.future;
      h.identity.change(null);
      gate.complete();
      expect((await transfer).status, LocalTextHandoffStatus.obsolete);
      expect(await body.close(), isFalse);
      expect(await body.close(abandonUnsaved: true), isTrue);
    });

    test(
      'closing while a handoff save is pending prevents text session creation',
      () async {
        final body = await h.editing();
        final gate = h.store.writeGate = Completer<void>();
        final transfer = body.handoffPlainText('paragraph');
        await h.store.writeStarted.future;
        final closing = body.close();
        gate.complete();
        expect((await transfer).status, LocalTextHandoffStatus.obsolete);
        expect(await closing, isTrue);
        expect(body.state.phase, LocalStructuredPhase.closed);
        expect(await h.inner.load(_key), isNotNull);
      },
    );

    test(
      'account replacement during close returns no text coordinator',
      () async {
        final body = await h.editing();
        final subscription = body.changes.listen((state) {
          if (state.phase == LocalStructuredPhase.closed) {
            h.identity.change('other');
          }
        });
        final result = await body.handoffPlainText('paragraph');
        expect(result.status, LocalTextHandoffStatus.obsolete);
        expect(result.session, isNull);
        expect(body.state.phase, LocalStructuredPhase.closed);
        expect((await h.inner.load(_key))!.key.userId, 'author');
        await subscription.cancel();
      },
    );

    test(
      'synchronous account changes from the store cannot leak a handoff',
      () async {
        final body = await h.editing();
        h.store.onWrite = () => h.identity.change('other');
        final result = await body.handoffPlainText('paragraph');
        expect(result.status, LocalTextHandoffStatus.obsolete);
        expect(result.session, isNull);
        expect(body.state.phase, LocalStructuredPhase.invalidated);
        expect(body.state.body, isNull);
      },
    );
  });

  group('exact revision fence between coordinators', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test(
      'body changed after handoff conflicts before the text editor opens',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        final original = (await h.inner.load(_key))!;
        final newer = (await h.inner.replace(
          expected: original,
          body: original.body.replacePlainText('paragraph', 'newer body'),
          updatedAt: _date,
        ))!;
        await text.open();
        expect(text.state.phase, LocalTextPhase.conflict);
        expect(text.state.body, isNull);
        expect(text.resume(), isFalse);
        expect(
          (await h.inner.load(_key))!.bodyStorageJson,
          newer.bodyStorageJson,
        );
      },
    );

    test('metadata changed after handoff cannot be silently adopted', () async {
      final body = await h.editing();
      final text = await h.handoff(body);
      final original = (await h.inner.load(_key))!;
      final newer = (await h.inner.replaceSession(
        expected: original,
        body: original.body,
        sessionMetadata: _metadata('other metadata'),
        updatedAt: _date,
      ))!;
      await text.open();
      expect(text.state.phase, LocalTextPhase.conflict);
      expect(
        (await h.inner.load(_key))!.sessionMetadataStorageJson,
        newer.sessionMetadataStorageJson,
      );
    });

    test(
      'external raw JSON change without revision increment fails closed',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        final original = (await h.inner.load(_key))!;
        await h.db.customStatement(
          'UPDATE structured_body_drafts SET body_blocks = ?',
          [' ${original.bodyStorageJson}'],
        );
        await text.open();
        expect(text.state.phase, LocalTextPhase.conflict);
        final changed = (await h.inner.load(_key))!;
        expect(changed.revision, original.revision);
        expect(changed.bodyStorageJson, ' ${original.bodyStorageJson}');
      },
    );

    test(
      'metadata raw bytes and timestamp also participate in the fence',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        final original = (await h.inner.load(_key))!;
        await h.db.customStatement(
          'UPDATE structured_body_drafts SET session_metadata = ?',
          [' ${original.sessionMetadataStorageJson}'],
        );
        await text.open();
        expect(text.state.phase, LocalTextPhase.conflict);
        final current = (await h.inner.load(_key))!;
        expect(current.revision, original.revision);
        expect(
          current.sessionMetadata!.toJson(),
          original.sessionMetadata!.toJson(),
        );
      },
    );

    test('timestamp changes without a revision update are detected', () async {
      final body = await h.editing();
      final text = await h.handoff(body);
      final original = (await h.inner.load(_key))!;
      await h.db.customStatement(
        'UPDATE structured_body_drafts SET updated_at = ?',
        [original.updatedAt.microsecondsSinceEpoch + 1],
      );
      await text.open();
      expect(text.state.phase, LocalTextPhase.conflict);
      expect((await h.inner.load(_key))!.revision, original.revision);
    });

    test(
      'a concurrent intermediate buffer is never adopted at handoff',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        final original = (await h.inner.load(_key))!;
        final competing = (await h.inner.createTextBuffer(
          expected: original,
          buffer: StructuredTextBuffer(
            blockId: 'paragraph',
            text: 'other pending',
          ),
          updatedAt: _date,
        ))!;
        await text.open();
        expect(text.state.phase, LocalTextPhase.conflict);
        expect(text.state.text, isNull);
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          competing.storageJson,
        );
      },
    );

    test(
      'a buffer inserted without advancing revision also blocks adoption',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        final original = (await h.inner.load(_key))!;
        final raw = StructuredTextBuffer(
          blockId: 'paragraph',
          text: '',
        ).encode();
        await h.db.customStatement(
          'UPDATE structured_body_drafts SET text_buffer = ?',
          [raw],
        );
        await text.open();
        expect(text.state.phase, LocalTextPhase.conflict);
        final saved = (await h.inner.loadTextBuffer(_key))!;
        expect(saved.parent.revision, original.revision);
        expect(saved.storageJson, raw);
      },
    );

    test(
      'deleted and recreated row cannot pass the saved incarnation fence',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        final old = (await h.inner.load(_key))!;
        expect(await h.inner.discard(old), isTrue);
        final newer = await h.seed();
        expect(newer.rowId, isNot(old.rowId));
        await text.open();
        expect(text.state.phase, LocalTextPhase.conflict);
        expect((await h.inner.load(_key))!.rowId, newer.rowId);
      },
    );

    test(
      'a damaged target is not repaired or loaded from the server',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        await h.db.customStatement(
          "UPDATE structured_body_drafts SET body_blocks = 'broken'",
        );
        await text.open();
        expect(text.state.phase, LocalTextPhase.loadFailed);
        expect(text.state.body, isNull);
        expect(h.reader.calls, 1);
        expect(
          await h.db
              .customSelect('SELECT body_blocks FROM structured_body_drafts')
              .getSingle()
              .then((row) => row.read<String>('body_blocks')),
          'broken',
        );
      },
    );

    test(
      'account change after handoff invalidates the new coordinator',
      () async {
        final body = await h.editing();
        final text = await h.handoff(body);
        h.identity.change('other');
        await text.open();
        expect(text.state.phase, LocalTextPhase.invalidated);
        expect(text.state.text, isNull);
        expect(text.resume(), isFalse);
        expect(await h.inner.load(_key), isNotNull);
      },
    );
  });

  group('offline indexed recovery handoff', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('selected indexed row retains combined buffer capability', () async {
      final saved = await h.seed();
      h.reader.result = const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
      final session = openIndexedRecovery(
        entry: StructuredRecoveryIndexEntry(rowId: saved.rowId, key: _key),
        fence: _fence,
        opener: h.opener,
      );
      h.bodies.add(session);
      await session.open();
      expect(session.state.phase, LocalStructuredPhase.recoveryChoice);
      expect(session.resumeRecovery(), isTrue);
      final text = await h.handoff(session);
      await text.open();
      expect(text.state.text, 'local');
      expect(text.resume(), isTrue);
      expect(text.edit('offline input'), isTrue);
      expect(await text.flush(), LocalTextFlushResult.saved);
      expect(
        (await h.inner.loadTextBuffer(_key))!.buffer.text,
        'offline input',
      );
      expect(h.reader.calls, 0);
    });

    test(
      'legacy body-only indexed store remains usable but cannot hand off',
      () async {
        final saved = await h.seed();
        final opener = OpenStructuredEditingSession(
          reader: h.reader,
          store: _BodyOnlyStore(h.inner),
          identity: h.identity,
        );
        final session = openIndexedRecovery(
          entry: StructuredRecoveryIndexEntry(rowId: saved.rowId, key: _key),
          fence: _fence,
          opener: opener,
        );
        h.bodies.add(session);
        await session.open();
        expect(session.resumeRecovery(), isTrue);
        expect(
          (await session.handoffPlainText('paragraph')).status,
          LocalTextHandoffStatus.unsupportedStore,
        );
        expect(session.state.phase, LocalStructuredPhase.editing);
        expect((await h.inner.load(_key))!.rowId, saved.rowId);
      },
    );

    test('selected row replacement before text open remains fenced', () async {
      final original = await h.seed();
      final session = openIndexedRecovery(
        entry: StructuredRecoveryIndexEntry(rowId: original.rowId, key: _key),
        fence: _fence,
        opener: h.opener,
      );
      h.bodies.add(session);
      await session.open();
      session.resumeRecovery();
      final text = await h.handoff(session);
      expect(await h.inner.discard(original), isTrue);
      final replacement = await h.seed();
      await text.open();
      expect([
        LocalTextPhase.conflict,
        LocalTextPhase.loadFailed,
      ], contains(text.state.phase));
      expect((await h.inner.load(_key))!.rowId, replacement.rowId);
    });
  });

  group('offline indexed intermediate buffer discovery', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    Future<StructuredTextBufferRecovery> seedBuffer(String input) async {
      final parent = await h.seed();
      return (await h.inner.createTextBuffer(
        expected: parent,
        buffer: StructuredTextBuffer(blockId: 'paragraph', text: input),
        updatedAt: _date,
      ))!;
    }

    OpenIndexedTextRecovery discovery() =>
        OpenIndexedTextRecovery(store: h.store, identity: h.identity);
    StructuredRecoveryIndexEntry entry(int rowId) =>
        StructuredRecoveryIndexEntry(rowId: rowId, key: _key);

    test('explicitly selected empty buffer can be recovered offline', () async {
      final saved = await seedBuffer('');
      final result = await discovery()(
        entry: entry(saved.parent.rowId),
        fence: _fence,
        isCurrent: () => true,
      );
      expect(result.status, IndexedTextRecoveryStatus.ready);
      final session = result.session!;
      h.texts.add(session);
      expect(session.state.phase, LocalTextPhase.initial);
      await session.open();
      expect(session.state.phase, LocalTextPhase.recoveryChoice);
      expect(session.state.text, '');
      expect(session.resume(), isTrue);
      expect(
        await session.apply(confirmed: true),
        LocalTextFinishResult.invalid,
      );
      expect(
        (await h.inner.loadTextBuffer(_key))!.storageJson,
        saved.storageJson,
      );
      expect(h.reader.calls, 0);
    });

    test('no buffer does not fabricate intermediate text', () async {
      final row = await h.seed();
      final result = await discovery()(
        entry: entry(row.rowId),
        fence: _fence,
        isCurrent: () => true,
      );
      expect(result.status, IndexedTextRecoveryStatus.noBuffer);
      expect(result.session, isNull);
      expect((await h.inner.load(_key))!.revision, row.revision);
    });

    test('corruption is unavailable and remains unchanged', () async {
      final saved = await seedBuffer('pending');
      await h.db.customStatement(
        "UPDATE structured_body_drafts SET text_buffer = '{bad'",
      );
      final result = await discovery()(
        entry: entry(saved.parent.rowId),
        fence: _fence,
        isCurrent: () => true,
      );
      expect(result.status, IndexedTextRecoveryStatus.unavailable);
      expect(result.session, isNull);
      final raw = await h.db
          .customSelect('SELECT text_buffer FROM structured_body_drafts')
          .getSingle();
      expect(raw.read<String>('text_buffer'), '{bad');
    });

    test('selected row incarnation cannot be replaced', () async {
      final saved = await seedBuffer('old');
      final cleared = (await h.inner.discardTextBuffer(
        expected: saved,
        updatedAt: _date,
      ))!;
      expect(await h.inner.discard(cleared), isTrue);
      final replacement = await seedBuffer('new');
      final result = await discovery()(
        entry: entry(saved.parent.rowId),
        fence: _fence,
        isCurrent: () => true,
      );
      expect(result.status, IndexedTextRecoveryStatus.changed);
      expect(result.session, isNull);
      expect(
        (await h.inner.loadTextBuffer(_key))!.storageJson,
        replacement.storageJson,
      );
    });

    test('newer buffered edit between discovery and open conflicts', () async {
      final saved = await seedBuffer('first');
      final result = await discovery()(
        entry: entry(saved.parent.rowId),
        fence: _fence,
        isCurrent: () => true,
      );
      final session = result.session!;
      h.texts.add(session);
      final next = (await h.inner.replaceTextBuffer(
        expected: saved,
        buffer: StructuredTextBuffer(blockId: 'paragraph', text: 'newer'),
        updatedAt: _date,
      ))!;
      await session.open();
      expect(session.state.phase, LocalTextPhase.conflict);
      expect(session.state.text, isNull);
      expect(
        (await h.inner.loadTextBuffer(_key))!.storageJson,
        next.storageJson,
      );
    });

    test(
      'raw buffer change without revision increment is not adopted',
      () async {
        final saved = await seedBuffer('first');
        final result = await discovery()(
          entry: entry(saved.parent.rowId),
          fence: _fence,
          isCurrent: () => true,
        );
        final session = result.session!;
        h.texts.add(session);
        final raw = StructuredTextBuffer(
          blockId: 'paragraph',
          text: 'external',
        ).encode();
        await h.db.customStatement(
          'UPDATE structured_body_drafts SET text_buffer = ?',
          [raw],
        );
        await session.open();
        expect(session.state.phase, LocalTextPhase.conflict);
        expect((await h.inner.loadTextBuffer(_key))!.storageJson, raw);
      },
    );

    test(
      'a buffer cleared after discovery is not silently treated as a body',
      () async {
        final saved = await seedBuffer('first');
        final result = await discovery()(
          entry: entry(saved.parent.rowId),
          fence: _fence,
          isCurrent: () => true,
        );
        final session = result.session!;
        h.texts.add(session);
        expect(
          await h.inner.discardTextBuffer(expected: saved, updatedAt: _date),
          isNotNull,
        );
        await session.open();
        expect(session.state.phase, LocalTextPhase.conflict);
        expect(session.state.text, isNull);
      },
    );

    test('route becoming obsolete during read hides the result', () async {
      final saved = await seedBuffer('private');
      final gate = h.store.bufferLoadGate = Completer<void>();
      var current = true;
      final future = discovery()(
        entry: entry(saved.parent.rowId),
        fence: _fence,
        isCurrent: () => current,
      );
      await h.store.bufferLoadStarted.future;
      current = false;
      gate.complete();
      final result = await future;
      expect(result.status, IndexedTextRecoveryStatus.obsolete);
      expect(result.session, isNull);
      expect(
        (await h.inner.loadTextBuffer(_key))!.storageJson,
        saved.storageJson,
      );
    });

    test('account switch during read hides the result', () async {
      final saved = await seedBuffer('private');
      final gate = h.store.bufferLoadGate = Completer<void>();
      final future = discovery()(
        entry: entry(saved.parent.rowId),
        fence: _fence,
        isCurrent: () => true,
      );
      await h.store.bufferLoadStarted.future;
      h.identity.change('other');
      gate.complete();
      final result = await future;
      expect(result.status, IndexedTextRecoveryStatus.obsolete);
      expect(result.session, isNull);
      expect(
        (await h.inner.loadTextBuffer(_key))!.storageJson,
        saved.storageJson,
      );
    });

    test('wrong account is refused before reading the store', () async {
      final saved = await seedBuffer('private');
      final result = await discovery()(
        entry: entry(saved.parent.rowId),
        fence: const NowaveSessionFence(userId: 'other', generation: 1),
        isCurrent: () => true,
      );
      expect(result.status, IndexedTextRecoveryStatus.obsolete);
      expect(h.store.bufferLoadStarted.isCompleted, isFalse);
    });
  });

  group('handoff and restart', () {
    test(
      'valid applied text preserves every unrelated field after reopening',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'handoff-restart-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/db.sqlite');
        final first = _Harness(database: AppDatabase(NativeDatabase(file)));
        final body = await first.editing();
        final text = await first.handoff(body);
        await text.open();
        expect(text.resume(), isTrue);
        expect(text.edit('new text 文本'), isTrue);
        expect(await text.flush(), LocalTextFlushResult.saved);
        expect(
          await text.apply(confirmed: true),
          LocalTextFinishResult.finished,
        );
        final before = (await first.inner.load(_key))!;
        await first.dispose();
        final second = _Harness(database: AppDatabase(NativeDatabase(file)));
        addTearDown(second.dispose);
        second.reader.result = const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.unavailable,
        );
        final reopened = await second.editing();
        expect(reopened.state.body!.blocks[2]['text'], 'new text 文本');
        for (var i = 0; i < _body().blocks.length; i++) {
          if (i != 2) {
            expect(reopened.state.body!.blocks[i], _body().blocks[i]);
          }
        }
        expect(
          reopened.state.metadata!.toJson(),
          _metadata('original').toJson(),
        );
        expect(
          (await second.inner.load(_key))!.baseStorageJson,
          before.baseStorageJson,
        );
        expect(await second.inner.loadTextBuffer(_key), isNull);
      },
    );

    test(
      'an empty input persists across restart as buffer, not valid body',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'handoff-empty-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/db.sqlite');
        final first = _Harness(database: AppDatabase(NativeDatabase(file)));
        final body = await first.editing();
        final text = await first.handoff(body);
        await text.open();
        text.resume();
        text.edit('');
        expect(await text.flush(), LocalTextFlushResult.saved);
        expect(
          await text.apply(confirmed: true),
          LocalTextFinishResult.invalid,
        );
        await first.dispose();
        final second = _Harness(database: AppDatabase(NativeDatabase(file)));
        addTearDown(second.dispose);
        final saved = (await second.inner.loadTextBuffer(_key))!;
        expect(saved.buffer.text, '');
        expect(saved.parent.body.blocks[2]['text'], 'literal **asterisks**');
        await expectLater(second.inner.load(_key), throwsFormatException);
      },
    );
  });
}
