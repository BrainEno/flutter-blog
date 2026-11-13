import 'dart:async';
import 'dart:io';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/open_indexed_recovery.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _backend = Uri.parse('https://catalog.example.invalid/api');
final _otherBackend = Uri.parse('https://other.example.invalid/api');
const _fence = NowaveSessionFence(userId: 'alice', generation: 7);

StructuredBodyKey _key(
  String article, {
  String user = 'alice',
  String locale = 'en',
}) => StructuredBodyKey(userId: user, articleId: article, locale: locale);
StructuredArticleDraft _body(String text) => StructuredArticleDraft.parse(
  version: 0,
  blocks: [
    {'id': 'p', 'type': 'paragraph', 'text': text},
    {
      'id': 'image',
      'type': 'image',
      'src': '/image.png',
      'alt': 'alt',
      'caption': 'caption',
    },
  ],
);

Future<StructuredBodyRecovery> _create(
  SqliteStructuredBodyRecoveryStore store,
  StructuredBodyKey key, {
  String text = 'local',
}) async => (await store.create(
  key: key,
  base: _body('base'),
  body: _body(text),
  updatedAt: DateTime.utc(2026),
))!;

class _Identity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'alice';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 7;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get identityChanges => events.stream;
  void switchTo(String id) {
    activeUserId = id;
    sessionGeneration++;
    events.add(null);
  }
}

class _NeverReader implements StructuredEditionReader {
  int calls = 0;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async {
    calls++;
    throw StateError('Network must not be contacted');
  }
}

void main() {
  late AppDatabase db;
  late SqliteStructuredBodyRecoveryStore store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: _backend);
  });
  tearDown(() async => db.close());

  test('empty account is not a failure or a remote deletion', () async {
    final page = await store.page(userId: 'alice');
    expect(page.entries, isEmpty);
    expect(page.nextCursor, isNull);
  });

  test(
    'only exact backend and account rows appear, including all editions',
    () async {
      await _create(store, _key('same', locale: 'en'));
      await _create(store, _key('same', locale: 'zh-CN'));
      await _create(store, _key('same', locale: 'zh-TW'));
      await _create(store, _key('private-bob', user: 'bob'));
      final other = SqliteStructuredBodyRecoveryStore(
        db,
        apiBaseUrl: _otherBackend,
      );
      await _create(other, _key('private-other'));
      final page = await store.page(userId: 'alice');
      expect(page.entries.map((e) => e.key!.locale), ['en', 'zh-CN', 'zh-TW']);
      expect(page.entries.map((e) => e.key!.articleId), everyElement('same'));
      expect(
        (await store.page(userId: 'bob')).entries.single.key!.articleId,
        'private-bob',
      );
      expect(
        (await other.page(userId: 'alice')).entries.single.key!.articleId,
        'private-other',
      );
      expect((await store.page(userId: 'nobody')).entries, isEmpty);
    },
  );

  test(
    'canonical backend namespace ignores credentials, query and fragment',
    () async {
      await _create(store, _key('one'));
      final equivalent = SqliteStructuredBodyRecoveryStore(
        db,
        apiBaseUrl: Uri.parse(
          'https://u:p@catalog.example.invalid/api/?secret=x#z',
        ),
      );
      expect(
        (await equivalent.page(userId: 'alice')).entries.single.key!.articleId,
        'one',
      );
    },
  );

  test('keyset pages are bounded, stable and never use timestamps', () async {
    for (var i = 0; i < 60; i++) {
      await _create(store, _key('work-$i'));
    }
    final one = await store.page(userId: 'alice');
    expect(one.entries, hasLength(25));
    expect(one.nextCursor, one.entries.last.rowId);
    final two = await store.page(userId: 'alice', afterRowId: one.nextCursor);
    final three = await store.page(userId: 'alice', afterRowId: two.nextCursor);
    expect(two.entries, hasLength(25));
    expect(three.entries, hasLength(10));
    expect(three.nextCursor, isNull);
    final ids = [
      ...one.entries,
      ...two.entries,
      ...three.entries,
    ].map((e) => e.rowId).toList();
    expect(ids.toSet(), hasLength(60));
    expect(ids, orderedEquals([...ids]..sort()));
    expect(
      [
        ...one.entries,
        ...two.entries,
        ...three.entries,
      ].map((e) => e.key!.articleId),
      [for (var i = 0; i < 60; i++) 'work-$i'],
    );
  });

  test(
    'inserts and deletions between pages do not duplicate existing rows',
    () async {
      final rows = <StructuredBodyRecovery>[];
      for (var i = 0; i < 30; i++) {
        rows.add(await _create(store, _key('work-$i')));
      }
      final one = await store.page(userId: 'alice');
      expect(await store.discard(rows[26]), isTrue);
      await _create(store, _key('new'));
      final two = await store.page(userId: 'alice', afterRowId: one.nextCursor);
      final names = two.entries.map((e) => e.key!.articleId).toList();
      expect(names, ['work-25', 'work-27', 'work-28', 'work-29', 'new']);
      expect(two.nextCursor, isNull);
    },
  );

  test('invalid identity and cursor are rejected before querying', () async {
    for (final user in ['', ' ', ' alice', 'alice ']) {
      await expectLater(store.page(userId: user), throwsArgumentError);
    }
    for (final cursor in [0, -1]) {
      await expectLater(
        store.page(userId: 'alice', afterRowId: cursor),
        throwsArgumentError,
      );
    }
  });

  test(
    'malformed identities are visible as unopenable and do not conceal healthy rows',
    () async {
      await _create(store, _key('broken'));
      await _create(store, _key('healthy'));
      await db.customStatement(
        "UPDATE structured_body_drafts SET locale = 'unknown' WHERE article_id = 'broken'",
      );
      final page = await store.page(userId: 'alice');
      expect(page.entries, hasLength(2));
      expect(page.entries.first.key, isNull);
      expect(page.entries.last.key!.articleId, 'healthy');
      expect(
        (await db.customSelect('SELECT id FROM structured_body_drafts').get()),
        hasLength(2),
      );
    },
  );

  test(
    'oversized identity remains unopenable without being copied into UI',
    () async {
      await _create(store, _key('broken'));
      await db.customUpdate(
        'UPDATE structured_body_drafts SET article_id = ?',
        variables: [Variable<String>('a' * 5000)],
      );
      final page = await store.page(userId: 'alice');
      expect(page.entries.single.key, isNull);
      expect(
        (await db
                .customSelect(
                  'SELECT length(article_id) AS n FROM structured_body_drafts',
                )
                .getSingle())
            .read<int>('n'),
        5000,
      );
    },
  );

  test('listing never parses body, even when it is corrupt', () async {
    await _create(store, _key('broken'));
    await db.customStatement(
      "UPDATE structured_body_drafts SET body_blocks = '{broken'",
    );
    final item = (await store.page(userId: 'alice')).entries.single;
    expect(item.key!.articleId, 'broken');
    await expectLater(store.load(item.key!), throwsFormatException);
    expect((await store.page(userId: 'alice')).entries, hasLength(1));
  });

  test(
    'offline selection re-reads exact row and requires explicit recovery',
    () async {
      final original = await _create(store, _key('one'));
      final item = (await store.page(userId: 'alice')).entries.single;
      final identity = _Identity();
      final reader = _NeverReader();
      final session = openIndexedRecovery(
        entry: item,
        fence: _fence,
        opener: OpenStructuredEditingSession(
          reader: reader,
          store: store,
          identity: identity,
        ),
      );
      await session.open();
      expect(reader.calls, 0);
      expect(session.state.phase, LocalStructuredPhase.recoveryChoice);
      expect(
        session.state.baseComparison,
        StructuredBaseComparison.remoteUnavailable,
      );
      expect(session.state.body!.blocks.first['text'], 'local');
      expect(session.cancelRecovery(), isTrue);
      expect((await store.load(_key('one')))!.rowId, original.rowId);
      expect(await session.close(), isTrue);
      await identity.events.close();
    },
  );

  test(
    'offline recovery edit persists via original CAS without remote request',
    () async {
      await _create(store, _key('one'));
      final item = (await store.page(userId: 'alice')).entries.single;
      final identity = _Identity();
      final reader = _NeverReader();
      final session = openIndexedRecovery(
        entry: item,
        fence: _fence,
        opener: OpenStructuredEditingSession(
          reader: reader,
          store: store,
          identity: identity,
        ),
      );
      await session.open();
      expect(session.resumeRecovery(), isTrue);
      expect(session.edit((body) => body.move('image', 0)), isTrue);
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await store.load(_key('one')))!;
      expect(saved.body.blocks.first['id'], 'image');
      expect(saved.body.blocks.first['alt'], 'alt');
      expect(saved.body.blocks.first['caption'], 'caption');
      expect(saved.base.blocks.first['text'], 'base');
      expect(reader.calls, 0);
      expect(await session.close(), isTrue);
      await identity.events.close();
    },
  );

  test(
    'deleted or recreated selected row cannot open another incarnation',
    () async {
      final old = await _create(store, _key('one'));
      final item = (await store.page(userId: 'alice')).entries.single;
      expect(await store.discard(old), isTrue);
      final replacement = await _create(store, _key('one'), text: 'newer');
      expect(replacement.rowId, isNot(old.rowId));
      final identity = _Identity();
      final reader = _NeverReader();
      final session = openIndexedRecovery(
        entry: item,
        fence: _fence,
        opener: OpenStructuredEditingSession(
          reader: reader,
          store: store,
          identity: identity,
        ),
      );
      await session.open();
      expect(session.state.phase, LocalStructuredPhase.localReadFailed);
      expect(session.state.body, isNull);
      expect(
        (await store.load(_key('one')))!.body.blocks.first['text'],
        'newer',
      );
      expect(await session.close(), isTrue);
      await identity.events.close();
    },
  );

  test(
    'identity switch after selection prevents reading the old row',
    () async {
      await _create(store, _key('one'));
      final item = (await store.page(userId: 'alice')).entries.single;
      final identity = _Identity();
      final reader = _NeverReader();
      final session = openIndexedRecovery(
        entry: item,
        fence: _fence,
        opener: OpenStructuredEditingSession(
          reader: reader,
          store: store,
          identity: identity,
        ),
      );
      identity.switchTo('bob');
      await session.open();
      expect(session.state.phase, LocalStructuredPhase.invalidated);
      expect(session.state.body, isNull);
      expect(
        (await store.load(_key('one')))!.body.blocks.first['text'],
        'local',
      );
      expect(await session.close(), isTrue);
      await identity.events.close();
    },
  );

  test('catalog survives database restart without server access', () async {
    final directory = await Directory.systemTemp.createTemp('recovery-index-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/data.sqlite');
    var disk = AppDatabase(NativeDatabase(file));
    final first = SqliteStructuredBodyRecoveryStore(disk, apiBaseUrl: _backend);
    final original = await _create(first, _key('persisted', locale: 'zh-TW'));
    await disk.close();
    disk = AppDatabase(NativeDatabase(file));
    addTearDown(disk.close);
    final restarted = SqliteStructuredBodyRecoveryStore(
      disk,
      apiBaseUrl: _backend,
    );
    final index = await restarted.page(userId: 'alice');
    expect(index.entries.single.rowId, original.rowId);
    expect(index.entries.single.key!.locale, 'zh-TW');
    expect(
      (await restarted.load(
        index.entries.single.key!,
      ))!.body.blocks.first['text'],
      'local',
    );
  });

  test(
    'selected recovery still detects a later competing local write',
    () async {
      final original = await _create(store, _key('one'));
      final item = (await store.page(userId: 'alice')).entries.single;
      final identity = _Identity();
      final reader = _NeverReader();
      final session = openIndexedRecovery(
        entry: item,
        fence: _fence,
        opener: OpenStructuredEditingSession(
          reader: reader,
          store: store,
          identity: identity,
        ),
      );
      await session.open();
      expect(session.resumeRecovery(), isTrue);
      final other = await store.replace(
        expected: original,
        body: _body('other session'),
        updatedAt: DateTime.utc(2027),
      );
      expect(other, isNotNull);
      expect(session.edit((body) => body.move('image', 0)), isTrue);
      expect(await session.flush(), LocalStructuredFlushResult.conflict);
      expect(session.state.hasUnsavedChanges, isTrue);
      expect(
        (await store.load(_key('one')))!.body.blocks.first['text'],
        'other session',
      );
      expect(await session.close(), isFalse);
      expect(await session.close(abandonUnsaved: true), isTrue);
      await identity.events.close();
    },
  );

  test('corrupt selected body is not flattened, deleted or exposed', () async {
    await _create(store, _key('broken'));
    final item = (await store.page(userId: 'alice')).entries.single;
    await db.customStatement(
      "UPDATE structured_body_drafts SET body_blocks = '{broken'",
    );
    final identity = _Identity();
    final session = openIndexedRecovery(
      entry: item,
      fence: _fence,
      opener: OpenStructuredEditingSession(
        reader: _NeverReader(),
        store: store,
        identity: identity,
      ),
    );
    await session.open();
    expect(session.state.phase, LocalStructuredPhase.localReadFailed);
    expect(session.state.body, isNull);
    expect((await store.page(userId: 'alice')).entries, hasLength(1));
    expect(await session.close(), isTrue);
    await identity.events.close();
  });

  test('unopenable selection and mismatched owner are refused', () async {
    final identity = _Identity();
    final reader = _NeverReader();
    final opener = OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    );
    expect(
      () => openIndexedRecovery(
        entry: const StructuredRecoveryIndexEntry(rowId: 1, key: null),
        fence: _fence,
        opener: opener,
      ),
      throwsArgumentError,
    );
    expect(
      () => openIndexedRecovery(
        entry: StructuredRecoveryIndexEntry(
          rowId: 1,
          key: _key('one', user: 'bob'),
        ),
        fence: _fence,
        opener: opener,
      ),
      throwsArgumentError,
    );
    expect(
      () => openIndexedRecovery(
        entry: StructuredRecoveryIndexEntry(rowId: 0, key: _key('one')),
        fence: _fence,
        opener: opener,
      ),
      throwsArgumentError,
    );
    await identity.events.close();
  });
}
