import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_editor_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/structured_article_fixtures.dart';

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

  void switchUser(String? user) {
    activeUserId = user;
    accessToken = user == null ? null : 'new-token';
    sessionGeneration++;
    events.add(null);
  }
}

class _Reader implements StructuredEditionReader {
  _Reader(this.result);
  StructuredEditionReadResult result;
  Completer<StructuredEditionReadResult>? pending;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) => pending?.future ?? Future.value(result);
}

class _Store implements StructuredBodyRecoveryStore {
  _Store(this.inner);
  final StructuredBodyRecoveryStore inner;
  bool failCreate = false;
  bool failLoad = false;
  bool hideNextLoad = false;
  bool gateAfterCreate = false;
  Completer<void>? createGate;
  final createStarted = Completer<void>();

  @override
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key) async {
    if (failLoad) throw StateError('disk failure');
    if (hideNextLoad) {
      hideNextLoad = false;
      return null;
    }
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
    if (!gateAfterCreate) {
      if (!createStarted.isCompleted) createStarted.complete();
      if (createGate != null) await createGate!.future;
    }
    if (failCreate) throw StateError('disk failure');
    final saved = await inner.create(
      key: key,
      base: base,
      body: body,
      updatedAt: updatedAt,
      baseMetadata: baseMetadata,
      sessionMetadata: sessionMetadata,
    );
    if (gateAfterCreate) {
      if (!createStarted.isCompleted) createStarted.complete();
      if (createGate != null) await createGate!.future;
    }
    return saved;
  }

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

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-uuid',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _backend = Uri.parse('https://api.example.invalid');

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredSessionMetadata _metadata() => StructuredSessionMetadata(
  slug: 'structured',
  title: 'Title',
  summary: '',
  workType: 'other',
  publicationState: 'draft',
  tags: null,
  categories: null,
  cover: null,
);

StructuredEditionReadResult _remote() => StructuredEditionReadResult.found(
  StructuredEdition(
    key: _key,
    body: _body(),
    metadata: _metadata(),
    rawArticle: {'id': 'article-uuid'},
    metadataIssues: const {},
  ),
);

class _Harness {
  _Harness() {
    db = AppDatabase(NativeDatabase.memory());
    inner = SqliteStructuredBodyRecoveryStore(db, apiBaseUrl: _backend);
    store = _Store(inner);
    identity = _Identity();
    reader = _Reader(_remote());
    session = LocalStructuredSession(
      key: _key,
      fence: _fence,
      opener: OpenStructuredEditingSession(
        reader: reader,
        store: store,
        identity: identity,
      ),
    );
  }
  late final AppDatabase db;
  late final SqliteStructuredBodyRecoveryStore inner;
  late final _Store store;
  late final _Identity identity;
  late final _Reader reader;
  late final LocalStructuredSession session;

  Future<void> seed({StructuredArticleDraft? body}) async {
    await inner.create(
      key: _key,
      base: _body(),
      body: body ?? _body().move('image-two', 1),
      updatedAt: DateTime.utc(2026),
      baseMetadata: _metadata(),
      sessionMetadata: _metadata(),
    );
  }

  Future<void> dispose() async {
    // Release controlled operations even when an assertion fails. Otherwise
    // teardown can wait forever for a gate the failed test never reached.
    final createGate = store.createGate;
    if (createGate != null && !createGate.isCompleted) createGate.complete();
    final pendingRead = reader.pending;
    if (pendingRead != null && !pendingRead.isCompleted) {
      pendingRead.complete(
        const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.unavailable,
        ),
      );
    }
    await session.close(abandonUnsaved: true);
    await identity.events.close();
    await db.close();
  }
}

Future<void> _open(
  WidgetTester tester,
  _Harness h, {
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
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StructuredLocalEditorPage(session: h.session),
                ),
              );
            },
            child: const Text('Open test editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open test editor'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollToStatus(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 2000));
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() async => h.dispose());

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'local-only and limited actions are localized at large text scale $locale',
      (tester) async {
        tester.view.physicalSize = const Size(400, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _open(tester, h, locale: locale, scale: 1.5);
        expect(
          find.text(
            locale.languageCode == 'en' ? 'Local structure editor' : '本地结构编辑',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale.languageCode == 'en' ? 'Nothing is published' : '不会发布',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale.languageCode == 'en'
                ? 'Images and list formatting are preserved'
                : '图片和列表格式会保留',
          ),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(locale.languageCode == 'en' ? 'Publish' : '发布'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reorders and toggles first run without losing IDs, links or image details',
    (tester) async {
      await _open(tester, h);
      await _tapVisible(
        tester,
        find.byTooltip('Toggle bold on first text run').first,
      );
      await _tapVisible(tester, find.byTooltip('Move block down').first);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final stored = (await h.inner.load(_key))!;
      final blocks = stored.body.toJsonBlocks();
      expect(blocks.map((block) => block['id']).take(3), [
        'image-one',
        'heading',
        'paragraph',
      ]);
      final heading = blocks[1];
      final runs = heading['inlines'] as List;
      expect(runs.first['marks'], isNot(contains('bold')));
      expect(runs.first['href'], '/guide');
      expect(runs.last['href'], 'https://external.example/path');
      expect(blocks.first['alt'], 'First image alt');
      expect(blocks.first['caption'], 'First caption');
      expect(stored.base.toJsonBlocks(), _body().toJsonBlocks());
      await _scrollToStatus(tester);
      expect(find.text('Saved on this device'), findsOneWidget);
    },
  );

  testWidgets(
    'delete requires confirmation and cancel preserves exact local snapshot',
    (tester) async {
      await _open(tester, h);
      await _tapVisible(tester, find.byTooltip('Remove block').first);
      expect(find.text('Remove this block?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
      await _tapVisible(tester, find.byTooltip('Remove block').first);
      await tester.tap(find.text('Remove block').last);
      await tester.pumpAndSettle();
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final stored = (await h.inner.load(_key))!;
      expect(
        stored.body.blocks.map((block) => block['id']),
        isNot(contains('heading')),
      );
      expect(stored.base.blocks.first['id'], 'heading');
    },
  );

  testWidgets(
    'recovery waits for an explicit choice, cancel leaves local data',
    (tester) async {
      await h.seed();
      await _open(tester, h);
      expect(find.text('Local recovery found'), findsOneWidget);
      expect(find.text('Resume local changes'), findsOneWidget);
      expect(find.byTooltip('Move block down'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final saved = (await h.inner.load(_key))!;
      expect(saved.body.blocks[1]['id'], 'image-two');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Open test editor'), findsOneWidget);
    },
  );

  testWidgets('recovery resumes offline and reports remote uncertainty', (
    tester,
  ) async {
    await h.seed();
    h.reader.result = const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.unavailable,
    );
    await _open(tester, h);
    expect(find.textContaining('could not be fully compared'), findsOneWidget);
    await tester.tap(find.text('Resume local changes'));
    await tester.pumpAndSettle();
    expect(h.session.state.phase, LocalStructuredPhase.editing);
    expect(h.session.state.body!.blocks[1]['id'], 'image-two');
    expect(find.text('Saved on this device'), findsOneWidget);
  });

  testWidgets('discard recovery confirmation defaults to preserving it', (
    tester,
  ) async {
    await h.seed();
    await _open(tester, h);
    await tester.tap(find.text('Discard local recovery'));
    await tester.pumpAndSettle();
    expect(find.text('Discard local recovery?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect((await h.inner.load(_key))!.body.blocks[1]['id'], 'image-two');
    expect(find.text('Local recovery found'), findsOneWidget);
    await tester.tap(find.text('Discard local recovery').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard local recovery').last);
    await tester.pumpAndSettle();
    expect(await h.inner.load(_key), isNull);
    expect(h.session.state.phase, LocalStructuredPhase.editing);
    expect(h.session.state.body!.blocks[1]['id'], 'image-one');
  });

  testWidgets('action tooltips are accessible and expose button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _open(tester, h);
      final control = find.byTooltip('Move block down').first;
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(control).getSemanticsData();
      expect(node.tooltip, 'Move block down');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'rapid repeated bold actions use the latest body, not a stale closure',
    (tester) async {
      await _open(tester, h);
      final bold = find.byTooltip('Toggle bold on first text run').first;
      await tester.ensureVisible(bold);
      await tester.pumpAndSettle();
      await tester.tap(bold);
      await tester.tap(bold);
      await tester.pumpAndSettle();
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final stored = (await h.inner.load(_key))!;
      final runs = stored.body.blocks.first['inlines'] as List;
      expect((runs.first as Map)['marks'], contains('bold'));
      expect((runs.first as Map)['href'], '/guide');
    },
  );

  for (final pair in <(StructuredEditionReadStatus, String)>[
    (
      StructuredEditionReadStatus.unsupportedDocument,
      'unsupported or damaged blocks',
    ),
    (StructuredEditionReadStatus.invalidResponse, 'could not be validated'),
    (StructuredEditionReadStatus.editionMismatch, 'different language edition'),
    (StructuredEditionReadStatus.authenticationRequired, 'Sign in again'),
    (StructuredEditionReadStatus.unavailable, 'Check the connection'),
  ]) {
    testWidgets(
      'remote failure ${pair.$1} is explicit and never creates a draft',
      (tester) async {
        h.reader.result = StructuredEditionReadResult.failed(pair.$1);
        await _open(tester, h);
        expect(find.textContaining(pair.$2), findsOneWidget);
        expect(find.byTooltip('Move block down'), findsNothing);
        expect(await h.inner.load(_key), isNull);
      },
    );
  }

  testWidgets('missing author-window entry never becomes an empty document', (
    tester,
  ) async {
    h.reader.result = const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.notInAuthorWindow,
    );
    await _open(tester, h);
    expect(find.textContaining('does not mean it was deleted'), findsOneWidget);
    expect(find.byTooltip('Move block down'), findsNothing);
    expect(await h.inner.load(_key), isNull);
  });

  testWidgets('corrupt recovery prevents opening the remote content', (
    tester,
  ) async {
    await h.seed();
    h.store.failLoad = true;
    await _open(tester, h);
    expect(
      find.textContaining('Local recovery could not be read'),
      findsOneWidget,
    );
    expect(find.byTooltip('Move block down'), findsNothing);
    expect((await h.inner.load(_key))!.body.blocks[1]['id'], 'image-two');
  });

  testWidgets('account change removes private content and disables actions', (
    tester,
  ) async {
    await _open(tester, h);
    expect(find.text('Bold代码'), findsOneWidget);
    h.identity.switchUser('other');
    await tester.pumpAndSettle();
    expect(
      find.text('The account changed. This session is no longer available.'),
      findsOneWidget,
    );
    expect(find.text('Bold代码'), findsNothing);
    expect(find.byTooltip('Move block down'), findsNothing);
    expect(await h.inner.load(_key), isNull);
  });

  testWidgets(
    'late remote response after account change cannot reveal its body',
    (tester) async {
      h.reader.pending = Completer<StructuredEditionReadResult>();
      await _open(tester, h);
      expect(find.textContaining('Loading the exact edition'), findsOneWidget);
      h.identity.switchUser('other');
      h.reader.pending!.complete(_remote());
      await tester.pumpAndSettle();
      expect(find.text('Bold代码'), findsNothing);
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
    },
  );

  testWidgets(
    'a confirmation open during account change cannot edit the new account',
    (tester) async {
      await _open(tester, h);
      await _tapVisible(tester, find.byTooltip('Remove block').first);
      h.identity.switchUser('other');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove block').last);
      await tester.pumpAndSettle();
      expect(find.text('Bold代码'), findsNothing);
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
    },
  );

  testWidgets(
    'save failure is visible; cancellation keeps pending changes for retry',
    (tester) async {
      h.store.failCreate = true;
      await _open(tester, h);
      await _tapVisible(tester, find.byTooltip('Move block down').first);
      expect(await h.session.flush(), LocalStructuredFlushResult.failed);
      await tester.pumpAndSettle();
      await _scrollToStatus(tester);
      expect(find.textContaining('Local save failed'), findsOneWidget);
      expect(h.session.state.hasUnsavedChanges, isTrue);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave with unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(h.session.state.phase, LocalStructuredPhase.saveFailed);
      expect(h.session.state.body!.blocks.first['id'], 'image-one');
      expect(await h.inner.load(_key), isNull);
      h.store.failCreate = false;
      await _tapVisible(tester, find.text('Retry'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      await tester.pumpAndSettle();
      expect((await h.inner.load(_key))!.body.blocks.first['id'], 'image-one');
      await _scrollToStatus(tester);
      expect(find.text('Saved on this device'), findsOneWidget);
    },
  );

  testWidgets(
    'explicitly leaving failed edits never deletes an existing local row',
    (tester) async {
      // Another session inserts a row after our initial load but before our
      // first create. Hide it from the initial read only; the real SQLite CAS
      // still sees it and must refuse the competing create.
      await h.seed();
      h.store.hideNextLoad = true;
      await _open(tester, h);
      await _tapVisible(tester, find.byTooltip('Move block down').first);
      expect(await h.session.flush(), LocalStructuredFlushResult.conflict);
      await tester.pumpAndSettle();
      await _scrollToStatus(tester);
      expect(
        find.textContaining('Another local session changed'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave with unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Leave and lose unsaved changes'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Open test editor'), findsOneWidget);
      expect((await h.inner.load(_key))!.body.blocks[1]['id'], 'image-two');
    },
  );

  testWidgets('system back waits for an admitted local write', (tester) async {
    h.store.createGate = Completer<void>();
    await _open(tester, h);
    await _tapVisible(tester, find.byTooltip('Move block down').first);
    expect(h.store.createStarted.isCompleted, isTrue);
    // Dispatching a system pop is asynchronous under WidgetTester. Pump its
    // observers rather than blocking the fake clock awaiting the dispatch.
    bool? handled;
    tester.binding.handlePopRoute().then((value) => handled = value);
    await tester.pump();
    expect(handled, isTrue);
    expect(find.byType(StructuredLocalEditorPage), findsOneWidget);
    h.store.createGate!.complete();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Open test editor'), findsOneWidget);
    expect((await h.inner.load(_key))!.body.blocks.first['id'], 'image-one');
  });

  testWidgets('background transition does not drop an admitted save', (
    tester,
  ) async {
    // Delay the acknowledgement after the real SQLite transaction commits.
    // Lifecycle flush must still wait for the writer and retain its result.
    h.store.gateAfterCreate = true;
    h.store.createGate = Completer<void>();
    await _open(tester, h);
    await _tapVisible(tester, find.byTooltip('Move block down').first);
    expect(h.store.createStarted.isCompleted, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(h.session.state.hasUnsavedChanges, isTrue);
    h.store.createGate!.complete();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(await h.session.flush(), LocalStructuredFlushResult.saved);
    expect((await h.inner.load(_key))!.body.blocks.first['id'], 'image-one');
  });

  testWidgets('single remaining block cannot be removed', (tester) async {
    final single = StructuredArticleDraft.parse(
      version: 0,
      blocks: [
        {'id': 'only', 'type': 'paragraph', 'text': 'Only paragraph'},
      ],
    );
    await h.seed(body: single);
    await _open(tester, h);
    await tester.tap(find.text('Resume local changes'));
    await tester.pumpAndSettle();
    final remove = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Remove block',
      ),
    );
    expect(remove.onPressed, isNull);
    expect(find.byTooltip('Toggle bold on first text run'), findsNothing);
    expect(h.session.state.body!.version, 0);
  });
}
