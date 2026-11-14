import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_inline_selection.dart';
import 'package:belog/features/blog/domain/editing/structured_inline_replacement.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

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

  void switchTo(String? user) {
    activeUserId = user;
    accessToken = user == null ? null : 'new-token';
    sessionGeneration++;
    events.add(null);
  }
}

class _Reader implements StructuredEditionReader {
  _Reader(this.result);
  StructuredEditionReadResult result;
  Completer<StructuredEditionReadResult>? gate;
  int calls = 0;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) {
    calls++;
    return gate?.future ?? Future.value(result);
  }
}

class _GateStore implements StructuredBodyRecoveryStore {
  _GateStore(this.inner);
  final StructuredBodyRecoveryStore inner;
  Completer<void>? createGate;
  Completer<void>? replaceGate;
  Completer<void>? discardGate;
  final createStarted = Completer<void>();
  final replaceStarted = Completer<void>();
  final discardStarted = Completer<void>();
  void Function()? onCreate;
  Object? createError;
  Object? replaceError;
  Object? loadError;
  Object? discardError;
  int creates = 0;
  int replaces = 0;
  int discards = 0;

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) async {
    if (loadError case final Object error) throw error;
    return inner.load(key);
  }

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
    onCreate?.call();
    if (!createStarted.isCompleted) createStarted.complete();
    final gate = createGate;
    if (gate != null) await gate.future;
    if (createError case final Object error) throw error;
    return inner.create(
      key: key,
      base: base,
      body: body,
      updatedAt: updatedAt,
      baseMetadata: baseMetadata,
      sessionMetadata: sessionMetadata,
    );
  }

  @override
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  }) => _replace(expected: expected, body: body, updatedAt: updatedAt);

  @override
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  }) => _replace(
    expected: expected,
    body: body,
    updatedAt: updatedAt,
    metadata: sessionMetadata,
  );

  Future<StructuredBodyRecovery?> _replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? metadata,
  }) async {
    replaces++;
    if (!replaceStarted.isCompleted) replaceStarted.complete();
    final gate = replaceGate;
    if (gate != null) await gate.future;
    if (replaceError case final Object error) throw error;
    return metadata == null
        ? inner.replace(expected: expected, body: body, updatedAt: updatedAt)
        : inner.replaceSession(
            expected: expected,
            body: body,
            updatedAt: updatedAt,
            sessionMetadata: metadata,
          );
  }

  @override
  Future<bool> discard(StructuredBodyRecovery expected) async {
    discards++;
    if (!discardStarted.isCompleted) discardStarted.complete();
    final gate = discardGate;
    if (gate != null) await gate.future;
    if (discardError case final Object error) throw error;
    return inner.discard(expected);
  }
}

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-uuid',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _time = DateTime.utc(2026, 10, 29);

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredSessionMetadata _metadata({
  String? title = 'Title',
  StructuredCoverSelection? cover,
}) => StructuredSessionMetadata(
  slug: 'slug',
  title: title,
  summary: '',
  workType: 'other',
  publicationState: 'draft',
  tags: StructuredTaxonomySelection(values: ['tag'], touched: false),
  categories: StructuredTaxonomySelection(values: ['category'], touched: false),
  cover: cover,
);

StructuredEditionReadResult _remote({
  StructuredBodyKey? key,
  StructuredArticleDraft? body,
  StructuredSessionMetadata? metadata,
  Set<StructuredMetadataIssue> issues = const {},
}) => StructuredEditionReadResult.found(
  StructuredEdition(
    key: key ?? _key,
    body: body ?? _body(),
    metadata: metadata ?? _metadata(),
    rawArticle: {'id': 'article-uuid'},
    metadataIssues: issues,
  ),
);

class _Harness {
  _Harness({StructuredEditionReadResult? remote, Uri? backend}) {
    db = AppDatabase(NativeDatabase.memory());
    inner = SqliteStructuredBodyRecoveryStore(
      db,
      apiBaseUrl: backend ?? Uri.parse('https://one.example'),
    );
    store = _GateStore(inner);
    reader = _Reader(remote ?? _remote());
    identity = _Identity();
    opener = OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    );
  }
  late final AppDatabase db;
  late final SqliteStructuredBodyRecoveryStore inner;
  late final _GateStore store;
  late final _Reader reader;
  late final _Identity identity;
  late final OpenStructuredEditingSession opener;
  final sessions = <LocalStructuredSession>[];

  LocalStructuredSession session({
    StructuredBodyKey? key,
    NowaveSessionFence fence = _fence,
  }) {
    final value = LocalStructuredSession(
      key: key ?? _key,
      fence: fence,
      opener: opener,
      now: () => _time,
    );
    sessions.add(value);
    return value;
  }

  Future<StructuredBodyRecovery> seed({
    StructuredBodyKey? key,
    StructuredArticleDraft? base,
    StructuredArticleDraft? body,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? metadata,
  }) async => (await inner.create(
    key: key ?? _key,
    base: base ?? _body(),
    body: body ?? _body().replacePlainText('paragraph', 'local'),
    updatedAt: _time,
    baseMetadata: baseMetadata,
    sessionMetadata: metadata,
  ))!;

  Future<void> dispose() async {
    // A conflict intentionally refuses ordinary close. Invalidate only after
    // assertions so cleanup cannot mask an unsafe deletion or lost update.
    identity.switchTo(null);
    for (final session in sessions) {
      await session.close(abandonUnsaved: true);
    }
    await identity.events.close();
    await db.close();
  }
}

String _text(StructuredArticleDraft? body) =>
    body!.blocks.firstWhere((b) => b['id'] == 'paragraph')['text'] as String;

void main() {
  late _Harness h;
  setUp(() {
    h = _Harness();
  });
  tearDown(() async {
    await h.dispose();
  });

  group('isolated inline replacement with the fenced local coordinator', () {
    test('saves exact replaced runs and keeps all other data', () async {
      final session = h.session();
      await session.open();
      final before = session.state.body!;
      final edit = StructuredInlineReplacement.textBlock(
        document: before,
        blockId: 'heading',
        start: 1,
        end: 3,
      );
      expect(
        session.edit(
          (current) => edit.apply(
            current,
            inserted: StructuredInsertedText(
              text: 'X',
              marks: ['code'],
              href: '/new',
            ),
          ),
        ),
        isTrue,
      );
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await h.inner.load(_key))!;
      final heading = saved.body.blocks.first;
      expect(heading['text'], 'BXd代码');
      expect(heading['level'], 2);
      final runs = heading['inlines'] as List;
      expect(runs.map((r) => r['text']).toList(), ['B', 'X', 'd', '代码']);
      expect(runs[0]['href'], '/guide');
      expect(runs[1], {
        'text': 'X',
        'marks': ['code'],
        'href': '/new',
      });
      expect(runs[2]['href'], '/guide');
      expect(runs[3], (before.blocks.first['inlines'] as List)[1]);
      expect(
        saved.body.blocks.skip(1).toList(),
        before.blocks.skip(1).toList(),
      );
      expect(saved.base.toJsonBlocks(), before.toJsonBlocks());
      expect(saved.sessionMetadata!.toJson(), _metadata().toJson());
    });

    test(
      'a stale replacement throws without starting a second write',
      () async {
        final session = h.session();
        await session.open();
        final edit = StructuredInlineReplacement.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 1,
          end: 3,
        );
        expect(session.edit((body) => body.move('image-two', 1)), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        final previous = (await h.inner.load(_key))!;
        expect(
          () => session.edit(
            (body) =>
                edit.apply(body, inserted: StructuredInsertedText(text: 'X')),
          ),
          throwsStateError,
        );
        final after = (await h.inner.load(_key))!;
        expect(after.revision, previous.revision);
        expect(after.body.toJsonBlocks(), previous.body.toJsonBlocks());
        expect(h.store.creates, 1);
        expect(h.store.replaces, 0);
      },
    );

    test(
      'identity change rejects a retained operation and starts no write',
      () async {
        final session = h.session();
        await session.open();
        final edit = StructuredInlineReplacement.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 1,
          end: 3,
        );
        h.identity.switchTo('other');
        expect(
          session.edit(
            (body) =>
                edit.apply(body, inserted: StructuredInsertedText(text: 'X')),
          ),
          isFalse,
        );
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(await h.inner.load(_key), isNull);
        expect(h.store.creates, 0);
      },
    );

    test(
      'accepted write during account switch remains under original key',
      () async {
        h.store.createGate = Completer<void>();
        final session = h.session();
        await session.open();
        final edit = StructuredInlineReplacement.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 1,
          end: 3,
        );
        expect(
          session.edit(
            (body) =>
                edit.apply(body, inserted: StructuredInsertedText(text: 'X')),
          ),
          isTrue,
        );
        await h.store.createStarted.future;
        h.identity.switchTo('other');
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        h.store.createGate!.complete();
        expect(await session.close(), isTrue);
        final saved = (await h.inner.load(_key))!;
        expect(saved.key.userId, 'author');
        expect(saved.body.blocks.first['text'], 'BXd代码');
        final other = StructuredBodyKey(
          userId: 'other',
          articleId: _key.articleId,
          locale: _key.locale,
        );
        expect(await h.inner.load(other), isNull);
      },
    );

    test(
      'disk failure keeps the replacement in memory until explicit retry',
      () async {
        h.store.createError = StateError('disk');
        final session = h.session();
        await session.open();
        final edit = StructuredInlineReplacement.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 1,
          end: 3,
        );
        expect(
          session.edit(
            (body) =>
                edit.apply(body, inserted: StructuredInsertedText(text: 'X')),
          ),
          isTrue,
        );
        expect(await session.flush(), LocalStructuredFlushResult.failed);
        expect(session.state.phase, LocalStructuredPhase.saveFailed);
        expect(session.state.hasUnsavedChanges, isTrue);
        expect(session.state.body!.blocks.first['text'], 'BXd代码');
        expect(await h.inner.load(_key), isNull);
        h.store.createError = null;
        expect(session.retrySave(), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        expect((await h.inner.load(_key))!.body.blocks.first['text'], 'BXd代码');
      },
    );

    test(
      'a competing local row triggers conflict without overwriting it',
      () async {
        final session = h.session();
        await session.open();
        final edit = StructuredInlineReplacement.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 1,
          end: 3,
        );
        final competing = await h.seed();
        expect(
          session.edit(
            (body) =>
                edit.apply(body, inserted: StructuredInsertedText(text: 'X')),
          ),
          isTrue,
        );
        expect(await session.flush(), LocalStructuredFlushResult.conflict);
        expect(session.state.hasUnsavedChanges, isTrue);
        expect(session.retrySave(), isFalse);
        final after = (await h.inner.load(_key))!;
        expect(after.rowId, competing.rowId);
        expect(after.revision, competing.revision);
        expect(after.body.toJsonBlocks(), competing.body.toJsonBlocks());
      },
    );

    test('sequential edits coalesce behind an in-flight write', () async {
      h.store.createGate = Completer<void>();
      final session = h.session();
      await session.open();
      final first = StructuredInlineReplacement.textBlock(
        document: session.state.body!,
        blockId: 'heading',
        start: 1,
        end: 3,
      );
      expect(
        session.edit(
          (body) =>
              first.apply(body, inserted: StructuredInsertedText(text: 'X')),
        ),
        isTrue,
      );
      await h.store.createStarted.future;
      final second = StructuredInlineReplacement.textBlock(
        document: session.state.body!,
        blockId: 'heading',
        start: 1,
        end: 2,
      );
      expect(
        session.edit(
          (body) => second.apply(
            body,
            inserted: StructuredInsertedText(text: 'YZ', marks: ['bold']),
          ),
        ),
        isTrue,
      );
      h.store.createGate!.complete();
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await h.inner.load(_key))!;
      expect(saved.body.blocks.first['text'], 'BYZd代码');
      expect((saved.body.blocks.first['inlines'] as List)[1], {
        'text': 'YZ',
        'marks': ['bold'],
      });
      expect(saved.revision, 2);
      expect(h.store.creates, 1);
      expect(h.store.replaces, 1);
    });

    test('saved replacement is recovered only after explicit resume', () async {
      final first = h.session();
      await first.open();
      final edit = StructuredInlineReplacement.textBlock(
        document: first.state.body!,
        blockId: 'heading',
        start: 1,
        end: 3,
      );
      expect(
        first.edit(
          (body) =>
              edit.apply(body, inserted: StructuredInsertedText(text: 'X')),
        ),
        isTrue,
      );
      expect(await first.flush(), LocalStructuredFlushResult.saved);
      expect(await first.close(), isTrue);
      final second = h.session();
      await second.open();
      expect(second.state.phase, LocalStructuredPhase.recoveryChoice);
      expect(second.state.body!.blocks.first['text'], 'BXd代码');
      expect(second.resumeRecovery(), isTrue);
      expect(second.state.phase, LocalStructuredPhase.editing);
      expect(second.state.body!.blocks.first['text'], 'BXd代码');
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        second.state.body!.toJsonBlocks(),
      );
    });
  });

  group('opening and explicit recovery decisions', () {
    test('remote edition opens without creating a local row', () async {
      final session = h.session();
      expect(session.state.phase, LocalStructuredPhase.initial);
      expect(await session.flush(), LocalStructuredFlushResult.notReady);
      await session.open();
      expect(session.state.phase, LocalStructuredPhase.editing);
      expect(session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
      expect(session.state.remoteStatus, StructuredEditionReadStatus.found);
      expect(
        session.state.baseComparison,
        StructuredBaseComparison.noLocalBase,
      );
      expect(await h.inner.load(_key), isNull);
      expect(h.store.creates, 0);
      await session.open();
      expect(h.reader.calls, 1);
    });

    test(
      'recovery requires an explicit decision and cancellation changes nothing',
      () async {
        final original = await h.seed(
          metadata: _metadata(title: 'local title'),
        );
        final session = h.session();
        await session.open();
        expect(session.state.phase, LocalStructuredPhase.recoveryChoice);
        expect(session.state.recoveryAvailable, isTrue);
        expect(_text(session.state.body), 'local');
        expect(session.state.metadata!.title, 'local title');
        expect(
          session.edit((body) => body.replacePlainText('paragraph', 'no')),
          isFalse,
        );
        expect(await session.discardRecovery(confirmed: false), isFalse);
        expect(h.store.discards, 0);
        expect(session.cancelRecovery(), isTrue);
        expect(session.state.phase, LocalStructuredPhase.cancelled);
        final saved = (await h.inner.load(_key))!;
        expect(saved.rowId, original.rowId);
        expect(saved.revision, original.revision);
        expect(_text(saved.body), 'local');
      },
    );

    test(
      'resume adopts the local body and unknown metadata without writing',
      () async {
        await h.seed();
        final session = h.session();
        await session.open();
        expect(session.resumeRecovery(), isTrue);
        expect(session.state.phase, LocalStructuredPhase.editing);
        expect(_text(session.state.body), 'local');
        expect(session.state.metadata, isNull);
        expect(session.state.recoveryAvailable, isTrue);
        expect(h.store.replaces, 0);
      },
    );

    test(
      'offline remote does not prevent resuming an existing local draft',
      () async {
        h.reader.result = const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.unavailable,
        );
        await h.seed();
        final session = h.session();
        await session.open();
        expect(session.state.phase, LocalStructuredPhase.recoveryChoice);
        expect(
          session.state.baseComparison,
          StructuredBaseComparison.remoteUnavailable,
        );
        expect(session.resumeRecovery(), isTrue);
        expect(_text(session.state.body), 'local');
        expect(
          session.edit(
            (body) => body.replacePlainText('paragraph', 'offline edit'),
          ),
          isTrue,
        );
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        expect(_text((await h.inner.load(_key))!.body), 'offline edit');
      },
    );

    test(
      'missing remote and missing recovery stay unavailable, never a blank draft',
      () async {
        h.reader.result = const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.notInAuthorWindow,
        );
        final session = h.session();
        await session.open();
        expect(session.state.phase, LocalStructuredPhase.unavailable);
        expect(
          session.state.remoteStatus,
          StructuredEditionReadStatus.notInAuthorWindow,
        );
        expect(session.state.body, isNull);
        expect(await session.flush(), LocalStructuredFlushResult.notReady);
        expect(session.edit((body) => body), isFalse);
        expect(await h.inner.load(_key), isNull);
      },
    );

    test(
      'local read corruption blocks remote initialization and does not overwrite',
      () async {
        final original = await h.seed();
        h.store.loadError = const FormatException('corrupt');
        final session = h.session();
        await session.open();
        expect(session.state.phase, LocalStructuredPhase.localReadFailed);
        expect(session.state.body, isNull);
        expect(session.edit((body) => body), isFalse);
        final saved = (await h.inner.load(_key))!;
        expect(saved.rowId, original.rowId);
        expect(_text(saved.body), 'local');
      },
    );

    test('rejects a remote edition from another key', () async {
      h.reader.result = _remote(
        key: StructuredBodyKey(
          userId: 'author',
          articleId: 'other',
          locale: 'en',
        ),
      );
      final session = h.session();
      await session.open();
      expect(session.state.phase, LocalStructuredPhase.localReadFailed);
      expect(session.state.body, isNull);
      expect(h.store.creates, 0);
    });
  });

  group('inline selections with local session fencing', () {
    test('rapid selections coalesce behind the existing CAS writer', () async {
      final session = h.session();
      await session.open();
      h.store.createGate = Completer<void>();
      final first = StructuredInlineSelection.textBlock(
        document: session.state.body!,
        blockId: 'heading',
        start: 0,
        end: 2,
      );
      expect(
        session.edit((body) => first.setMark(body, 'code', enabled: true)),
        isTrue,
      );
      await h.store.createStarted.future;
      final second = StructuredInlineSelection.textBlock(
        document: session.state.body!,
        blockId: 'heading',
        start: 2,
        end: 4,
      );
      expect(session.edit((body) => second.setLink(body, '/new')), isTrue);
      h.store.createGate!.complete();
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      final row = (await h.inner.load(_key))!;
      expect(row.body.blocks[0]['text'], 'Bold代码');
      final runs = row.body.blocks[0]['inlines'] as List;
      expect(runs.first['text'], 'Bo');
      expect((runs.first['marks'] as List).contains('code'), isTrue);
      expect(runs[1]['text'], 'ld');
      expect(runs[1]['href'], '/new');
      expect(runs[2], (_body().blocks[0]['inlines'] as List)[1]);
      expect(row.body.blocks[1], _body().blocks[1]);
    });

    test(
      'an old selection is rejected synchronously before any new save',
      () async {
        final session = h.session();
        await session.open();
        final old = StructuredInlineSelection.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 0,
          end: 2,
        );
        expect(session.edit((body) => body.move('image-one', 2)), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        final count = h.store.replaces;
        expect(
          () => session.edit((body) => old.setLink(body, '/x')),
          throwsStateError,
        );
        expect(h.store.replaces, count);
        expect((await h.inner.load(_key))!.body.blocks[2]['id'], 'image-one');
      },
    );

    test(
      'failed storage keeps a formatted edit until explicit retry',
      () async {
        final session = h.session();
        await session.open();
        h.store.createError = StateError('disk');
        final range = StructuredInlineSelection.textBlock(
          document: session.state.body!,
          blockId: 'quote',
          start: 0,
          end: 3,
        );
        expect(session.edit((body) => range.setLink(body, '/local')), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.failed);
        expect(session.state.phase, LocalStructuredPhase.saveFailed);
        expect(
          (session.state.body!.blocks[3]['inlines'] as List).first['href'],
          '/local',
        );
        expect(await h.inner.load(_key), isNull);
        expect(await session.close(), isFalse);
        h.store.createError = null;
        expect(session.retrySave(), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        final saved = (await h.inner.load(_key))!;
        expect(
          (saved.body.blocks[3]['inlines'] as List).first['href'],
          '/local',
        );
        expect(saved.body.blocks[3]['attribution'], 'Author name');
      },
    );

    test(
      'competing local revision stops a formatted edit without overwrite',
      () async {
        final original = await h.seed(body: _body());
        final session = h.session();
        await session.open();
        expect(session.resumeRecovery(), isTrue);
        final other = (await h.inner.replace(
          expected: original,
          body: original.body.replacePlainText('paragraph', 'other writer'),
          updatedAt: _time,
        ))!;
        final range = StructuredInlineSelection.textBlock(
          document: session.state.body!,
          blockId: 'heading',
          start: 0,
          end: 2,
        );
        expect(session.edit((body) => range.setLink(body, '/mine')), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.conflict);
        expect(session.state.hasUnsavedChanges, isTrue);
        expect((await h.inner.load(_key))!.revision, other.revision);
        expect(_text((await h.inner.load(_key))!.body), 'other writer');
        expect(session.retrySave(), isFalse);
        expect(await session.close(), isFalse);
      },
    );

    test('account changes hide formatted state and reject new edits', () async {
      final session = h.session();
      await session.open();
      h.store.createGate = Completer<void>();
      final range = StructuredInlineSelection.textBlock(
        document: session.state.body!,
        blockId: 'heading',
        start: 0,
        end: 2,
      );
      expect(session.edit((body) => range.setLink(body, '/private')), isTrue);
      await h.store.createStarted.future;
      h.identity.switchTo('other');
      expect(session.state.phase, LocalStructuredPhase.invalidated);
      expect(session.state.body, isNull);
      expect(
        session.edit((body) => range.setMark(body, 'bold', enabled: true)),
        isFalse,
      );
      h.store.createGate!.complete();
      expect(await session.close(), isTrue);
      final saved = (await h.inner.load(_key))!;
      expect(
        (saved.body.blocks.first['inlines'] as List).first['href'],
        '/private',
      );
    });
  });

  group('base comparison is advisory', () {
    test('changed remote body is explicit', () async {
      await h.seed();
      h.reader.result = _remote(
        body: _body().replacePlainText('paragraph', 'remote changed'),
      );
      final session = h.session();
      await session.open();
      expect(
        session.state.baseComparison,
        StructuredBaseComparison.bodyDiffers,
      );
      expect(_text(session.state.body), 'local');
    });

    test(
      'missing base metadata and unknown fields cannot prove equality',
      () async {
        await h.seed();
        final session = h.session();
        await session.open();
        expect(
          session.state.baseComparison,
          StructuredBaseComparison.metadataUnknown,
        );
      },
    );

    test(
      'known matching metadata still refuses to infer an unknown cover',
      () async {
        await h.seed(baseMetadata: _metadata());
        final session = h.session();
        await session.open();
        expect(
          session.state.baseComparison,
          StructuredBaseComparison.metadataUnknown,
        );
      },
    );

    test(
      'compares complete represented metadata without claiming atomicity',
      () async {
        final complete = _metadata(cover: StructuredCoverSelection.unchanged());
        await h.seed(baseMetadata: complete);
        h.reader.result = _remote(metadata: complete);
        final session = h.session();
        await session.open();
        expect(
          session.state.baseComparison,
          StructuredBaseComparison.representedFieldsMatch,
        );
      },
    );

    test(
      'known metadata difference is surfaced independently of body',
      () async {
        await h.seed(
          baseMetadata: _metadata(cover: StructuredCoverSelection.unchanged()),
        );
        h.reader.result = _remote(
          metadata: _metadata(
            title: 'remote title',
            cover: StructuredCoverSelection.unchanged(),
          ),
        );
        final session = h.session();
        await session.open();
        expect(
          session.state.baseComparison,
          StructuredBaseComparison.metadataDiffers,
        );
      },
    );
  });

  group('durable serialized edits', () {
    test('first edit creates a recovery with exact base and body', () async {
      final session = h.session();
      await session.open();
      expect(
        session.edit(
          (body) => body.replacePlainText('paragraph', 'new local text'),
        ),
        isTrue,
      );
      expect(session.state.saving, isTrue);
      expect(session.state.hasUnsavedChanges, isTrue);
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      final stored = (await h.inner.load(_key))!;
      expect(stored.base.toJsonBlocks(), _body().toJsonBlocks());
      expect(_text(stored.body), 'new local text');
      expect(stored.baseMetadata!.toJson(), _metadata().toJson());
      expect(stored.sessionMetadata!.toJson(), _metadata().toJson());
      expect(stored.updatedAt, _time);
      expect(stored.revision, 1);
      expect(session.state.hasUnsavedChanges, isFalse);
      expect(session.state.saving, isFalse);
    });

    test(
      'rapid edits coalesce after an in-flight create and keep the latest',
      () async {
        h.store.createGate = Completer<void>();
        final session = h.session();
        await session.open();
        session.edit((body) => body.replacePlainText('paragraph', 'first'));
        await h.store.createStarted.future;
        session.edit((body) => body.replacePlainText('paragraph', 'second'));
        session.edit((body) => body.replacePlainText('paragraph', 'third'));
        final flushing = session.flush();
        h.store.createGate!.complete();
        expect(await flushing, LocalStructuredFlushResult.saved);
        expect(h.store.creates, 1);
        expect(h.store.replaces, 1);
        final saved = (await h.inner.load(_key))!;
        expect(_text(saved.body), 'third');
        expect(saved.revision, 2);
        expect(_text(saved.base), 'literal **asterisks**');
      },
    );

    test('editing from a state listener cannot strand a queued edit', () async {
      final session = h.session();
      await session.open();
      var editedFromListener = false;
      final sub = session.changes.listen((state) {
        if (state.phase == LocalStructuredPhase.editing &&
            !state.saving &&
            state.recoveryAvailable &&
            !editedFromListener) {
          editedFromListener = true;
          session.edit(
            (body) => body.replacePlainText('paragraph', 'listener edit'),
          );
        }
      });
      session.edit((body) => body.replacePlainText('paragraph', 'first'));
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      expect(editedFromListener, isTrue);
      expect(_text((await h.inner.load(_key))!.body), 'listener edit');
      await sub.cancel();
    });

    test(
      'formatted runs, image attributes, order and IDs survive saving',
      () async {
        final session = h.session();
        await session.open();
        expect(
          session.edit(
            (body) => body.setTextRunMark('heading', 0, 'code', enabled: true),
          ),
          isTrue,
        );
        expect(session.edit((body) => body.move('image-two', 1)), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        final saved = (await h.inner.load(_key))!;
        final blocks = saved.body.toJsonBlocks();
        expect(blocks.map((b) => b['id']), [
          'heading',
          'image-two',
          'image-one',
          'paragraph',
          'quote',
          'list',
          'code',
        ]);
        final heading = blocks.first;
        expect((heading['inlines'] as List).first['marks'], contains('code'));
        expect((heading['inlines'] as List).first['href'], '/guide');
        expect(blocks[1]['alt'], 'Second image alt');
        expect(blocks[1]['caption'], 'Second caption');
        expect(saved.base.toJsonBlocks(), _body().toJsonBlocks());
      },
    );

    test(
      'metadata edit and body edit save atomically with original metadata intact',
      () async {
        final session = h.session();
        await session.open();
        final edited = _metadata(
          title: 'new title',
          cover: StructuredCoverSelection.local(
            mimeType: 'image/png',
            bytes: [1, 2, 3],
          ),
        );
        session.edit((body) => body.replacePlainText('paragraph', 'new text'));
        session.editMetadata(edited);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        final saved = (await h.inner.load(_key))!;
        expect(_text(saved.body), 'new text');
        expect(saved.sessionMetadata!.title, 'new title');
        expect(saved.sessionMetadata!.cover!.bytes, [1, 2, 3]);
        expect(saved.baseMetadata!.title, 'Title');
        expect(saved.baseMetadata!.cover, isNull);
      },
    );

    test(
      'legacy unknown metadata stays null when changing only the body',
      () async {
        await h.seed();
        final session = h.session();
        await session.open();
        expect(session.resumeRecovery(), isTrue);
        session.edit(
          (body) => body.replacePlainText('paragraph', 'changed legacy'),
        );
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        final saved = (await h.inner.load(_key))!;
        expect(saved.baseMetadata, isNull);
        expect(saved.sessionMetadata, isNull);
        expect(_text(saved.body), 'changed legacy');
      },
    );

    test(
      'invalid operation leaves the previous body and store untouched',
      () async {
        final session = h.session();
        await session.open();
        expect(
          () => session.edit(
            (body) => body.replacePlainText('heading', 'would lose inlines'),
          ),
          throwsStateError,
        );
        expect(session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
        expect(await h.inner.load(_key), isNull);
        expect(h.store.creates, 0);
      },
    );

    test(
      'local storage failure preserves unsaved edit and blocks close',
      () async {
        h.store.createError = StateError('disk unavailable');
        final session = h.session();
        await session.open();
        session.edit((body) => body.replacePlainText('paragraph', 'unsaved'));
        expect(await session.flush(), LocalStructuredFlushResult.failed);
        expect(session.state.phase, LocalStructuredPhase.saveFailed);
        expect(_text(session.state.body), 'unsaved');
        expect(session.state.hasUnsavedChanges, isTrue);
        expect(await session.close(), isFalse);
        expect(await h.inner.load(_key), isNull);
        expect(session.edit((body) => body), isFalse);
        h.store.createError = null;
        expect(session.retrySave(), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        expect(_text((await h.inner.load(_key))!.body), 'unsaved');
        expect(await session.close(), isTrue);
        expect(session.state.phase, LocalStructuredPhase.closed);
      },
    );

    test(
      'a create conflict retains the other editor and the current unsaved edit',
      () async {
        h.store.createGate = Completer<void>();
        final session = h.session();
        await session.open();
        session.edit(
          (body) => body.replacePlainText('paragraph', 'my unsaved'),
        );
        await h.store.createStarted.future;
        final other = await h.seed(
          body: _body().replacePlainText('paragraph', 'other editor'),
        );
        h.store.createGate!.complete();
        expect(await session.flush(), LocalStructuredFlushResult.conflict);
        expect(session.state.phase, LocalStructuredPhase.conflict);
        expect(_text(session.state.body), 'my unsaved');
        expect(session.state.hasUnsavedChanges, isTrue);
        expect(session.retrySave(), isFalse);
        expect(await session.close(), isFalse);
        final saved = (await h.inner.load(_key))!;
        expect(saved.rowId, other.rowId);
        expect(_text(saved.body), 'other editor');
      },
    );

    test(
      'a replace conflict does not overwrite a newer local revision',
      () async {
        final original = await h.seed();
        final session = h.session();
        await session.open();
        session.resumeRecovery();
        h.store.replaceGate = Completer<void>();
        session.edit((body) => body.replacePlainText('paragraph', 'my edit'));
        await h.store.replaceStarted.future;
        final other = await h.inner.replace(
          expected: original,
          body: _body().replacePlainText('paragraph', 'other edit'),
          updatedAt: _time,
        );
        expect(other, isNotNull);
        h.store.replaceGate!.complete();
        expect(await session.flush(), LocalStructuredFlushResult.conflict);
        expect(_text(session.state.body), 'my edit');
        expect(_text((await h.inner.load(_key))!.body), 'other edit');
      },
    );

    test(
      'retry after uncertain create cannot overwrite an already committed row',
      () async {
        h.store.createError = StateError('unknown outcome');
        final session = h.session();
        await session.open();
        session.edit((body) => body.replacePlainText('paragraph', 'my edit'));
        expect(await session.flush(), LocalStructuredFlushResult.failed);
        await h.seed(
          body: _body().replacePlainText('paragraph', 'committed earlier'),
        );
        h.store.createError = null;
        expect(session.retrySave(), isTrue);
        expect(await session.flush(), LocalStructuredFlushResult.conflict);
        expect(_text((await h.inner.load(_key))!.body), 'committed earlier');
        expect(_text(session.state.body), 'my edit');
      },
    );
  });

  group('discard protection', () {
    test(
      'confirmed discard uses the exact recovery token before opening remote',
      () async {
        await h.seed();
        final session = h.session();
        await session.open();
        expect(await session.discardRecovery(confirmed: true), isTrue);
        expect(await h.inner.load(_key), isNull);
        expect(session.state.phase, LocalStructuredPhase.editing);
        expect(session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
        expect(h.store.discards, 1);
      },
    );

    test(
      'confirmed discard when offline deletes only the local revision and leaves unavailable',
      () async {
        await h.seed();
        h.reader.result = const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.unavailable,
        );
        final session = h.session();
        await session.open();
        expect(await session.discardRecovery(confirmed: true), isTrue);
        expect(session.state.phase, LocalStructuredPhase.unavailable);
        expect(await h.inner.load(_key), isNull);
      },
    );

    test(
      'discard cannot race recovery or close while the delete is pending',
      () async {
        await h.seed();
        h.store.discardGate = Completer<void>();
        final session = h.session();
        await session.open();
        final pending = session.discardRecovery(confirmed: true);
        await h.store.discardStarted.future;
        expect(session.resumeRecovery(), isFalse);
        expect(session.cancelRecovery(), isFalse);
        expect(await session.close(), isFalse);
        expect(await session.discardRecovery(confirmed: true), isFalse);
        h.store.discardGate!.complete();
        expect(await pending, isTrue);
      },
    );

    test('stale discard refuses to delete a newer snapshot', () async {
      final original = await h.seed();
      final session = h.session();
      await session.open();
      await h.inner.replace(
        expected: original,
        body: _body().replacePlainText('paragraph', 'newer'),
        updatedAt: _time,
      );
      expect(await session.discardRecovery(confirmed: true), isFalse);
      expect(session.state.phase, LocalStructuredPhase.conflict);
      expect(_text((await h.inner.load(_key))!.body), 'newer');
    });

    test('storage failure while discarding preserves local data', () async {
      await h.seed();
      h.store.discardError = StateError('disk');
      final session = h.session();
      await session.open();
      expect(await session.discardRecovery(confirmed: true), isFalse);
      expect(session.state.phase, LocalStructuredPhase.localReadFailed);
      expect(session.state.recoveryAvailable, isTrue);
      expect(_text((await h.inner.load(_key))!.body), 'local');
    });
  });

  group('identity, lifetime and isolation', () {
    test(
      'session replacement during remote read hides response and skips recovery',
      () async {
        final gate = Completer<StructuredEditionReadResult>();
        h.reader.gate = gate;
        final session = h.session();
        final opening = session.open();
        h.identity.switchTo('other');
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        gate.complete(_remote());
        await opening;
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(await session.flush(), LocalStructuredFlushResult.obsolete);
        expect(await h.inner.load(_key), isNull);
      },
    );

    test(
      'same account replacement invalidates even when user id is unchanged',
      () async {
        final session = h.session();
        await session.open();
        h.identity.switchTo('author');
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(session.edit((body) => body), isFalse);
      },
    );

    test(
      'identity getters fence even if a fake emits no change event',
      () async {
        final session = h.session();
        await session.open();
        h.identity.activeUserId = 'other';
        h.identity.sessionGeneration++;
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(session.edit((body) => body), isFalse);
      },
    );

    test(
      'accepted writes finish under their original account after switch',
      () async {
        h.store.createGate = Completer<void>();
        final session = h.session();
        await session.open();
        session.edit((body) => body.replacePlainText('paragraph', 'first'));
        await h.store.createStarted.future;
        session.edit(
          (body) => body.replacePlainText('paragraph', 'last before switch'),
        );
        h.identity.switchTo('other');
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(session.edit((body) => body), isFalse);
        h.store.createGate!.complete();
        expect(await session.close(), isTrue);
        final old = (await h.inner.load(_key))!;
        expect(_text(old.body), 'last before switch');
        final otherKey = StructuredBodyKey(
          userId: 'other',
          articleId: _key.articleId,
          locale: _key.locale,
        );
        expect(await h.inner.load(otherKey), isNull);
      },
    );

    test(
      'close waits for accepted writes and rejects edits while waiting',
      () async {
        h.store.createGate = Completer<void>();
        final session = h.session();
        await session.open();
        session.edit((body) => body.replacePlainText('paragraph', 'pending'));
        await h.store.createStarted.future;
        final closing = session.close();
        expect(session.edit((body) => body), isFalse);
        expect(await session.close(), isFalse);
        h.store.createGate!.complete();
        expect(await closing, isTrue);
        expect(_text((await h.inner.load(_key))!.body), 'pending');
        expect(session.state.phase, LocalStructuredPhase.closed);
      },
    );

    test(
      'close while opening ignores the late read without creating a row',
      () async {
        h.reader.gate = Completer<StructuredEditionReadResult>();
        final session = h.session();
        final pending = session.open();
        expect(await session.close(), isTrue);
        h.reader.gate!.complete(_remote());
        await pending;
        expect(session.state.phase, LocalStructuredPhase.closed);
        expect(await h.inner.load(_key), isNull);
      },
    );

    test(
      'changes stream stops emitting private snapshots after identity change',
      () async {
        final session = h.session();
        final states = <LocalStructuredState>[];
        final sub = session.changes.listen(states.add);
        await session.open();
        h.identity.switchTo('other');
        expect(states.last.phase, LocalStructuredPhase.invalidated);
        expect(states.last.body, isNull);
        expect(states.last.metadata, isNull);
        expect(states.last.remoteStatus, isNull);
        await sub.cancel();
      },
    );

    test(
      'drafts for other locales, article IDs and backends remain untouched',
      () async {
        final otherLocale = StructuredBodyKey(
          userId: 'author',
          articleId: 'article-uuid',
          locale: 'zh-CN',
        );
        final otherArticle = StructuredBodyKey(
          userId: 'author',
          articleId: 'other',
          locale: 'en',
        );
        final otherUser = StructuredBodyKey(
          userId: 'other',
          articleId: 'article-uuid',
          locale: 'en',
        );
        for (final key in [otherLocale, otherArticle, otherUser]) {
          await h.seed(
            key: key,
            body: _body().replacePlainText('paragraph', 'isolated'),
          );
        }
        final otherBackend = SqliteStructuredBodyRecoveryStore(
          h.db,
          apiBaseUrl: Uri.parse('https://two.example'),
        );
        await otherBackend.create(
          key: _key,
          base: _body(),
          body: _body().replacePlainText('paragraph', 'other backend'),
          updatedAt: _time,
        );
        final session = h.session();
        await session.open();
        session.edit(
          (body) => body.replacePlainText('paragraph', 'this edition'),
        );
        expect(await session.flush(), LocalStructuredFlushResult.saved);
        for (final key in [otherLocale, otherArticle, otherUser]) {
          expect(_text((await h.inner.load(key))!.body), 'isolated');
        }
        expect(_text((await otherBackend.load(_key))!.body), 'other backend');
        expect(_text((await h.inner.load(_key))!.body), 'this edition');
      },
    );

    test(
      'reopen observes saved local changes and asks again before recovery',
      () async {
        final first = h.session();
        await first.open();
        first.edit(
          (body) => body.replacePlainText('paragraph', 'persisted edit'),
        );
        expect(await first.flush(), LocalStructuredFlushResult.saved);
        expect(await first.close(), isTrue);
        final second = h.session();
        await second.open();
        expect(second.state.phase, LocalStructuredPhase.recoveryChoice);
        expect(_text(second.state.body), 'persisted edit');
        expect(second.resumeRecovery(), isTrue);
        expect(_text(second.state.body), 'persisted edit');
      },
    );

    test(
      'unexpected reader failure cannot initialize or save a blank draft',
      () async {
        h.reader.gate = Completer<StructuredEditionReadResult>();
        final session = h.session();
        final pending = session.open();
        h.reader.gate!.completeError(StateError('bad adapter'));
        await pending;
        expect(session.state.phase, LocalStructuredPhase.localReadFailed);
        expect(session.state.body, isNull);
        expect(await h.inner.load(_key), isNull);
      },
    );

    test(
      'failed accepted write after account switch is not silently abandoned',
      () async {
        h.store.createGate = Completer<void>();
        h.store.createError = StateError('disk failure');
        final session = h.session();
        await session.open();
        session.edit((body) => body.replacePlainText('paragraph', 'pending'));
        await h.store.createStarted.future;
        h.identity.switchTo('other');
        h.store.createGate!.complete();
        expect(await session.close(), isFalse);
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(await h.inner.load(_key), isNull);
        expect(await session.close(abandonUnsaved: true), isTrue);
      },
    );

    test(
      'identity switch inside an edit operation cannot resurrect the old body',
      () async {
        final session = h.session();
        await session.open();
        final accepted = session.edit((body) {
          h.identity.switchTo('other');
          return body.replacePlainText('paragraph', 'private');
        });
        expect(accepted, isFalse);
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(h.store.creates, 0);
      },
    );

    test(
      'identity switch while starting a store write never republishes private state',
      () async {
        final session = h.session();
        await session.open();
        h.store.onCreate = () => h.identity.switchTo('other');
        expect(
          session.edit(
            (body) => body.replacePlainText('paragraph', 'old owner'),
          ),
          isTrue,
        );
        expect(session.state.phase, LocalStructuredPhase.invalidated);
        expect(session.state.body, isNull);
        expect(await session.close(), isTrue);
        expect(_text((await h.inner.load(_key))!.body), 'old owner');
      },
    );

    test('reentrant operation cannot overwrite a newer edit', () async {
      final session = h.session();
      await session.open();
      final accepted = session.edit((body) {
        session.edit(
          (current) => current.replacePlainText('paragraph', 'newer'),
        );
        return body.replacePlainText('paragraph', 'stale');
      });
      expect(accepted, isFalse);
      expect(await session.flush(), LocalStructuredFlushResult.saved);
      expect(_text((await h.inner.load(_key))!.body), 'newer');
    });

    test('invalid account or fence cannot start a read', () async {
      final key = StructuredBodyKey(
        userId: 'other',
        articleId: 'article-uuid',
        locale: 'en',
      );
      final session = h.session(key: key);
      await session.open();
      expect(session.state.phase, LocalStructuredPhase.invalidated);
      expect(h.reader.calls, 0);
    });
  });
}
