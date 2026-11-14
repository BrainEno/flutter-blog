import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
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
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_buffer_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_editor_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_text_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_recovery_catalog_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/structured_article_fixtures.dart';

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'stable-id',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _time = DateTime.utc(2026);

StructuredArticleDraft _body() {
  final fixture = structuredArticle();
  return StructuredArticleDraft.parse(
    version: fixture['contentBlocksVersion'],
    blocks: fixture['contentBlocks'],
  );
}

StructuredSessionMetadata _metadata() => StructuredSessionMetadata(
  slug: 'slug',
  title: 'title',
  summary: '',
  workType: 'essay',
  publicationState: 'draft',
  tags: null,
  categories: null,
  cover: null,
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
  void change(String? value) {
    activeUserId = value;
    accessToken = value == null ? null : 'other';
    sessionGeneration++;
    events.add(null);
  }
}

class _Reader implements StructuredEditionReader {
  int calls = 0;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async {
    calls++;
    return StructuredEditionReadResult.found(
      StructuredEdition(
        key: key,
        body: _body(),
        metadata: _metadata(),
        rawArticle: {'id': key.articleId},
        metadataIssues: const {},
      ),
    );
  }
}

/// Uses the real SQLite implementation; only buffer acknowledgements are
/// controlled so widget tests can cover failures and lifecycle transitions.
class _Store implements StructuredTextSessionStore {
  _Store(this.inner);
  final SqliteStructuredBodyRecoveryStore inner;
  bool failBuffer = false;
  bool failFinish = false;
  Completer<void>? gate;
  bool gateAfterWrite = false;
  final writeStarted = Completer<void>();
  int bufferWrites = 0;
  int applyCalls = 0;
  int discardCalls = 0;

  Future<void> _wait() async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (gate case final value?) await value.future;
    if (failBuffer) throw StateError('storage');
  }

  @override
  Future<StructuredTextBufferRecovery?> loadTextBuffer(StructuredBodyKey key) =>
      inner.loadTextBuffer(key);
  @override
  Future<StructuredTextBufferRecovery?> createTextBuffer({
    required StructuredBodyRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    bufferWrites++;
    if (!gateAfterWrite) await _wait();
    final result = await inner.createTextBuffer(
      expected: expected,
      buffer: buffer,
      updatedAt: updatedAt,
    );
    if (gateAfterWrite) await _wait();
    return result;
  }

  @override
  Future<StructuredTextBufferRecovery?> replaceTextBuffer({
    required StructuredTextBufferRecovery expected,
    required StructuredTextBuffer buffer,
    required DateTime updatedAt,
  }) async {
    bufferWrites++;
    if (!gateAfterWrite) await _wait();
    final result = await inner.replaceTextBuffer(
      expected: expected,
      buffer: buffer,
      updatedAt: updatedAt,
    );
    if (gateAfterWrite) await _wait();
    return result;
  }

  @override
  Future<StructuredBodyRecovery?> applyTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    applyCalls++;
    if (failFinish) throw StateError('storage');
    return inner.applyTextBuffer(expected: expected, updatedAt: updatedAt);
  }

  @override
  Future<StructuredBodyRecovery?> discardTextBuffer({
    required StructuredTextBufferRecovery expected,
    required DateTime updatedAt,
  }) async {
    discardCalls++;
    if (failFinish) throw StateError('storage');
    return inner.discardTextBuffer(expected: expected, updatedAt: updatedAt);
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

class _ObservedBodySession extends LocalStructuredSession {
  _ObservedBodySession({
    required super.key,
    required super.fence,
    required super.opener,
    required super.now,
  });
  final completed = Completer<LocalTextHandoffResult>();
  bool started = false;
  @override
  Future<LocalTextHandoffResult> handoffPlainText(String blockId) async {
    started = true;
    final result = await super.handoffPlainText(blockId);
    completed.complete(result);
    return result;
  }
}

class _Harness {
  _Harness() {
    db = AppDatabase(NativeDatabase.memory());
    inner = SqliteStructuredBodyRecoveryStore(
      db,
      apiBaseUrl: Uri.parse('https://example.invalid/v1'),
    );
    store = _Store(inner);
    identity = _Identity();
    reader = _Reader();
    opener = OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    );
    body = _ObservedBodySession(
      key: _key,
      fence: _fence,
      opener: opener,
      now: () => _time,
    );
    user = AppUserCubit()
      ..updateUser(
        User(
          id: 'author',
          email: 'a@example.invalid',
          name: 'author',
          updatedAt: _time,
        ),
      );
  }
  late final AppDatabase db;
  late final SqliteStructuredBodyRecoveryStore inner;
  late final _Store store;
  late final _Identity identity;
  late final _Reader reader;
  late final OpenStructuredEditingSession opener;
  late final _ObservedBodySession body;
  late final AppUserCubit user;
  final textSessions = <LocalStructuredTextSession>[];

  Future<StructuredBodyRecovery> seed() async => (await inner.create(
    key: _key,
    base: _body(),
    body: _body(),
    updatedAt: _time,
    baseMetadata: _metadata(),
    sessionMetadata: _metadata(),
  ))!;
  Future<StructuredTextBufferRecovery> seedBuffer(String value) async {
    final row = await seed();
    return (await inner.createTextBuffer(
      expected: row,
      buffer: StructuredTextBuffer(blockId: 'paragraph', text: value),
      updatedAt: _time,
    ))!;
  }

  Future<LocalStructuredTextSession> direct({String? saved}) async {
    final parent = saved == null
        ? await seed()
        : (await seedBuffer(saved)).parent;
    final session = LocalStructuredTextSession(
      key: _key,
      selectedRowId: parent.rowId,
      blockId: 'paragraph',
      fence: _fence,
      identity: identity,
      store: store,
      now: () => _time,
    );
    textSessions.add(session);
    return session;
  }

  Future<void> dispose() async {
    if (store.gate case final gate?) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final session in textSessions) {
      await session.close(abandonUnsaved: true);
    }
    await body.close(abandonUnsaved: true);
    await identity.events.close();
    await user.close();
    await db.close();
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => page));
            },
            child: const Text('Open test page'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open test page'));
  await tester.pumpAndSettle();
}

Future<void> _visibleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _handoffFromBody(WidgetTester tester, _Harness h) async {
  await _visibleTap(tester, find.byTooltip('Edit unformatted text'));
  // pumpAndSettle only waits for scheduled frames; the SQLite handoff can
  // still be finishing without a frame. Wait for the admitted write first.
  for (var i = 0; i < 50 && !h.body.completed.isCompleted; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    h.body.completed.isCompleted,
    isTrue,
    reason:
        'handoff started: ${h.body.started}; body phase: ${h.body.state.phase}; block: ${h.body.state.body?.blocks[2]}',
  );
  final result = await h.body.completed.future;
  expect(result.status, LocalTextHandoffStatus.ready);
  await tester.pumpAndSettle();
}

Future<void> _startText(
  WidgetTester tester,
  _Harness h, {
  String? saved,
  Locale locale = const Locale('en'),
}) async {
  final session = await h.direct(saved: saved);
  await _pump(
    tester,
    StructuredLocalTextPage(session: session),
    locale: locale,
  );
  await tester.tap(
    find.text(locale.languageCode == 'en' ? 'Continue local text' : '继续编辑本地文字'),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('local body to plain text screen', () {
    testWidgets('only an unformatted text block exposes the edit action', (
      tester,
    ) async {
      await _pump(tester, StructuredLocalEditorPage(session: h.body));
      expect(find.byTooltip('Edit unformatted text'), findsOneWidget);
      expect(find.text('Publish'), findsNothing);
      await _handoffFromBody(tester, h);
      expect(
        find.byType(StructuredLocalTextPage),
        findsOneWidget,
        reason:
            'body phase: ${h.body.state.phase}; local row: ${await h.inner.load(_key)}; error: ${tester.takeException()}',
      );
      expect(find.text('Local recovery found'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(h.body.state.phase, LocalStructuredPhase.closed);
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        _body().toJsonBlocks(),
      );
      await tester.tap(find.text('Continue local text'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'literal **asterisks**',
      );
    });

    testWidgets('handoff freezes old editor and exits both pages after apply', (
      tester,
    ) async {
      await _pump(tester, StructuredLocalEditorPage(session: h.body));
      await _handoffFromBody(tester, h);
      await tester.tap(find.text('Continue local text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new local words');
      await tester.pumpAndSettle();
      await _visibleTap(tester, find.text('Apply to local body'));
      expect(find.text('Apply text to the local body?'), findsOneWidget);
      await tester.tap(find.text('Apply to local body').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(StructuredLocalTextPage), findsNothing);
      expect(find.byType(StructuredLocalEditorPage), findsNothing);
      expect(find.text('Open test page'), findsOneWidget);
      final saved = (await h.inner.load(_key))!;
      expect(saved.body.blocks[2]['text'], 'new local words');
      expect(saved.body.blocks[0], _body().blocks[0]);
      expect(saved.body.blocks[1], _body().blocks[1]);
      expect(saved.base.toJsonBlocks(), _body().toJsonBlocks());
      expect(await h.inner.loadTextBuffer(_key), isNull);
      expect(h.reader.calls, 1);
    });

    testWidgets('canceling text recovery leaves the parent untouched', (
      tester,
    ) async {
      await _pump(tester, StructuredLocalEditorPage(session: h.body));
      await _handoffFromBody(tester, h);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        _body().toJsonBlocks(),
      );
      expect(await h.inner.loadTextBuffer(_key), isNull);
    });
  });

  group('text editing, decisions, and storage', () {
    testWidgets(
      'explicit recovery is required even for an empty saved buffer',
      (tester) async {
        final session = await h.direct(saved: '');
        await _pump(tester, StructuredLocalTextPage(session: session));
        expect(find.text('Local recovery found'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Publish'), findsNothing);
        await tester.tap(find.text('Continue local text'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '',
        );
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, '');
      },
    );

    testWidgets('rapid input keeps the newest local buffer and exact body', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'one');
      await tester.enterText(find.byType(TextField), 'two');
      await tester.enterText(find.byType(TextField), 'final 世界');
      await tester.pumpAndSettle();
      expect(await h.textSessions.single.flush(), LocalTextFlushResult.saved);
      final saved = (await h.inner.loadTextBuffer(_key))!;
      expect(saved.buffer.text, 'final 世界');
      expect(saved.parent.body.toJsonBlocks(), _body().toJsonBlocks());
      expect(find.textContaining('local body is unchanged'), findsOneWidget);
    });

    testWidgets('empty input stays recoverable and cannot be applied', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await _visibleTap(tester, find.text('Apply to local body'));
      await tester.tap(find.text('Apply to local body').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be applied yet'), findsOneWidget);
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, '');
      expect(h.store.applyCalls, 0);
      expect(find.byType(StructuredLocalTextPage), findsOneWidget);
    });

    testWidgets('canceling apply confirmation does not change the buffer', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.pumpAndSettle();
      await _visibleTap(tester, find.text('Apply to local body'));
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(h.store.applyCalls, 0);
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'pending');
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('discard requires confirmation and keeps the local body', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'discard me');
      await tester.pumpAndSettle();
      await _visibleTap(tester, find.text('Discard text buffer'));
      expect(find.text('Discard this text buffer?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'discard me');
      await _visibleTap(tester, find.text('Discard text buffer'));
      await tester.tap(find.text('Discard text buffer').last);
      await tester.pumpAndSettle();
      expect(await h.inner.loadTextBuffer(_key), isNull);
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        _body().toJsonBlocks(),
      );
      expect(h.store.discardCalls, 1);
    });

    testWidgets('back keeps a persisted buffer without applying it', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'leave safely');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final saved = (await h.inner.loadTextBuffer(_key))!;
      expect(saved.buffer.text, 'leave safely');
      expect(saved.parent.body.toJsonBlocks(), _body().toJsonBlocks());
      expect(h.store.applyCalls, 0);
      expect(h.store.discardCalls, 0);
    });

    testWidgets('a failed save retains further typing until explicit retry', (
      tester,
    ) async {
      h.store.failBuffer = true;
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'first');
      await tester.pumpAndSettle();
      expect(find.textContaining('Local save failed'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'latest after failure');
      await tester.pumpAndSettle();
      expect(h.textSessions.single.state.text, 'latest after failure');
      expect(h.textSessions.single.state.hasUnsavedChanges, isTrue);
      expect(await h.inner.loadTextBuffer(_key), isNull);
      h.store.failBuffer = false;
      await _visibleTap(tester, find.text('Retry'));
      expect(await h.textSessions.single.flush(), LocalTextFlushResult.saved);
      await tester.pumpAndSettle();
      expect(
        (await h.inner.loadTextBuffer(_key))!.buffer.text,
        'latest after failure',
      );
    });

    testWidgets('leaving failed edits requires explicit confirmation', (
      tester,
    ) async {
      h.store.failBuffer = true;
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'unsaved input');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave with unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'unsaved input',
      );
      expect(h.textSessions.single.state.hasUnsavedChanges, isTrue);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave and lose unsaved changes'));
      await tester.pumpAndSettle();
      expect(await h.inner.loadTextBuffer(_key), isNull);
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        _body().toJsonBlocks(),
      );
    });

    testWidgets(
      'stale CAS shows conflict and never overwrites the other buffer',
      (tester) async {
        await _startText(tester, h, saved: 'initial');
        final existing = (await h.inner.loadTextBuffer(_key))!;
        final other = (await h.inner.replaceTextBuffer(
          expected: existing,
          buffer: StructuredTextBuffer(
            blockId: 'paragraph',
            text: 'other editor',
          ),
          updatedAt: _time,
        ))!;
        await tester.enterText(find.byType(TextField), 'my pending text');
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Another local session changed'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'my pending text',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          other.storageJson,
        );
        expect(h.textSessions.single.state.hasUnsavedChanges, isTrue);
      },
    );

    testWidgets('failed apply is distinct from saving and can be retried', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'saved text');
      await tester.pumpAndSettle();
      h.store.failFinish = true;
      await _visibleTap(tester, find.text('Apply to local body'));
      await tester.tap(find.text('Apply to local body').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('action could not be confirmed'),
        findsOneWidget,
      );
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'saved text');
      h.store.failFinish = false;
      await _visibleTap(tester, find.text('Apply to local body'));
      await tester.tap(find.text('Apply to local body').last);
      await tester.pumpAndSettle();
      expect((await h.inner.load(_key))!.body.blocks[2]['text'], 'saved text');
    });

    testWidgets(
      'UTF-16 input bound rejects oversized edits without truncating',
      (tester) async {
        await _startText(tester, h);
        await tester.enterText(find.byType(TextField), 'safe');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '😀' * 10001);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'safe',
        );
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'safe');
      },
    );
  });

  group('identity, recovery and accessibility', () {
    testWidgets(
      'identity change removes the text field and its controller value',
      (tester) async {
        await _startText(tester, h);
        await tester.enterText(find.byType(TextField), 'private input');
        await tester.pumpAndSettle();
        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        h.identity.change('other');
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('private input'), findsNothing);
        expect(controller.text, '');
        expect(find.textContaining('account changed'), findsOneWidget);
        expect(
          (await h.inner.loadTextBuffer(_key))!.buffer.text,
          'private input',
        );
      },
    );

    testWidgets('confirmation cannot apply after the account changes', (
      tester,
    ) async {
      await _startText(tester, h);
      await tester.enterText(find.byType(TextField), 'private');
      await tester.pumpAndSettle();
      await _visibleTap(tester, find.text('Apply to local body'));
      h.identity.change('other');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to local body').last);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(h.store.applyCalls, 0);
      expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'private');
    });

    testWidgets(
      'background lifecycle does not discard an acknowledged buffer',
      (tester) async {
        h.store.gateAfterWrite = true;
        h.store.gate = Completer<void>();
        await _startText(tester, h);
        await tester.enterText(find.byType(TextField), 'background');
        await tester.pumpAndSettle();
        expect(h.store.writeStarted.isCompleted, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        h.store.gate!.complete();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(await h.textSessions.single.flush(), LocalTextFlushResult.saved);
        expect((await h.inner.loadTextBuffer(_key))!.buffer.text, 'background');
      },
    );

    for (final locale in [const Locale('en'), const Locale('zh')]) {
      testWidgets('localized accessible text input at large scale $locale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final session = await h.direct();
          await _pump(
            tester,
            StructuredLocalTextPage(session: session),
            locale: locale,
            scale: 1.5,
          );
          expect(
            find.text(
              locale.languageCode == 'en' ? 'Edit local text' : '编辑本地文字',
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.text(
              locale.languageCode == 'en' ? 'Continue local text' : '继续编辑本地文字',
            ),
          );
          await tester.pumpAndSettle();
          final field = find.byType(TextField);
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          final node = tester.getSemantics(field).getSemanticsData();
          expect(node.flagsCollection.isTextField, isTrue);
          expect(
            find.text(locale.languageCode == 'en' ? 'Block text' : '区块文字'),
            findsOneWidget,
          );
          expect(
            find.text(locale.languageCode == 'en' ? 'Publish' : '发布'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets(
      'offline catalog opens a buffered recovery without the network',
      (tester) async {
        final saved = await h.seedBuffer('offline input');
        final list = ListStructuredRecoveries(
          catalog: h.inner,
          identity: h.identity,
        );
        await _pump(
          tester,
          StructuredRecoveryCatalogPage(
            list: list,
            opener: h.opener,
            user: h.user,
            fence: _fence,
          ),
        );
        expect(find.text('stable-id'), findsOneWidget);
        await tester.tap(find.text('stable-id'));
        await tester.pumpAndSettle();
        expect(find.byType(StructuredLocalTextPage), findsOneWidget);
        expect(find.text('Local recovery found'), findsOneWidget);
        expect(find.text('offline input'), findsNothing);
        await tester.tap(find.text('Continue local text'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'offline input',
        );
        expect(
          (await h.inner.loadTextBuffer(_key))!.storageJson,
          saved.storageJson,
        );
        expect(h.reader.calls, 0);
      },
    );

    testWidgets(
      'catalog rejects damaged buffers instead of opening a remote body',
      (tester) async {
        await h.seedBuffer('private');
        await h.db.customStatement(
          "UPDATE structured_body_drafts SET text_buffer = '{bad'",
        );
        final list = ListStructuredRecoveries(
          catalog: h.inner,
          identity: h.identity,
        );
        await _pump(
          tester,
          StructuredRecoveryCatalogPage(
            list: list,
            opener: h.opener,
            user: h.user,
            fence: _fence,
          ),
        );
        await tester.tap(find.text('stable-id'));
        await tester.pumpAndSettle();
        expect(find.byType(StructuredLocalTextPage), findsNothing);
        expect(
          find.textContaining('Local recovery could not be read'),
          findsOneWidget,
        );
        expect(h.reader.calls, 0);
        expect(
          (await h.db
                  .customSelect(
                    'SELECT text_buffer FROM structured_body_drafts',
                  )
                  .getSingle())
              .read<String>('text_buffer'),
          '{bad',
        );
      },
    );

    testWidgets('catalog UI-account change hides the open text immediately', (
      tester,
    ) async {
      await h.seedBuffer('private');
      final list = ListStructuredRecoveries(
        catalog: h.inner,
        identity: h.identity,
      );
      await _pump(
        tester,
        StructuredRecoveryCatalogPage(
          list: list,
          opener: h.opener,
          user: h.user,
          fence: _fence,
        ),
      );
      await tester.tap(find.text('stable-id'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue local text'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      h.user.updateUser(
        User(
          id: 'other',
          email: 'b@example.invalid',
          name: 'other',
          updatedAt: _time,
        ),
      );
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('private'), findsNothing);
      expect(find.textContaining('account changed'), findsOneWidget);
    });
  });
}
