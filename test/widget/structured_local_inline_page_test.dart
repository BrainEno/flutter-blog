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
import 'package:belog/features/blog/presentation/editor/structured_local_inline_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

Future<void> _openInline(WidgetTester tester, _Harness h) async {
  await _open(tester, h);
  await _tapVisible(tester, find.byTooltip('Edit text-run formatting').first);
  expect(find.byType(StructuredLocalInlinePage), findsOneWidget);
}

Finder _run(int index) => find.byKey(ValueKey('structured-inline-run-$index'));
Finder _withinRun(int index, String text) => find.descendant(
  of: _run(index),
  matching: text == 'Edit link' || text == '编辑链接'
      ? find.widgetWithText(OutlinedButton, text)
      : find.widgetWithText(FilterChip, text),
);

Future<void> _tapRun(WidgetTester tester, int index, String text) async {
  if (_run(index).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      _run(index),
      250,
      scrollable: find.descendant(
        of: find.byType(StructuredLocalInlinePage),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await _tapVisible(tester, _withinRun(index, text));
}

StructuredEditionReadResult _remoteWith(StructuredArticleDraft body) =>
    StructuredEditionReadResult.found(
      StructuredEdition(
        key: _key,
        body: body,
        metadata: _metadata(),
        rawArticle: {'id': 'article-uuid'},
        metadataIssues: const {},
      ),
    );

List<dynamic> _headingRuns(StructuredArticleDraft body) =>
    body.blocks.firstWhere((block) => block['id'] == 'heading')['inlines']
        as List;

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('entry and exact run formatting', () {
    testWidgets('v1 text blocks expose formatting, not lists or images', (
      tester,
    ) async {
      await _open(tester, h);
      for (final id in ['heading', 'image-one', 'paragraph', 'quote', 'list']) {
        final card = find.byKey(ValueKey(id));
        if (card.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            card,
            250,
            scrollable: find.byType(Scrollable).first,
          );
        }
        final action = find.descendant(
          of: card,
          matching: find.byTooltip('Edit text-run formatting'),
        );
        expect(
          action,
          ['heading', 'paragraph', 'quote'].contains(id)
              ? findsOneWidget
              : findsNothing,
          reason: id,
        );
      }
      expect(find.byTooltip('Edit unformatted text'), findsNothing);
      expect(find.text('Publish'), findsNothing);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('v0 refuses inline actions without upgrading the body', (
      tester,
    ) async {
      final body = StructuredArticleDraft.parse(
        version: 0,
        blocks: [
          {'id': 'p', 'type': 'paragraph', 'text': 'plain'},
          {
            'id': 'l',
            'type': 'list',
            'ordered': false,
            'items': ['one'],
          },
        ],
      );
      h.reader.result = _remoteWith(body);
      await _open(tester, h);
      expect(find.byTooltip('Edit text-run formatting'), findsNothing);
      expect(find.byTooltip('Toggle bold on first text run'), findsNothing);
      expect(h.session.state.body!.version, 0);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('opens a local-only screen without creating a recovery', (
      tester,
    ) async {
      await _openInline(tester, h);
      expect(find.text('Local text-run formatting'), findsOneWidget);
      expect(
        find.textContaining('one complete existing text run'),
        findsOneWidget,
      );
      expect(find.text('Text run 1'), findsOneWidget);
      expect(find.text('Bold'), findsWidgets);
      expect(find.text('Publish'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('toggles one whole run and preserves other run and link', (
      tester,
    ) async {
      await _openInline(tester, h);
      final original = _body();
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await h.inner.load(_key))!;
      final runs = _headingRuns(saved.body);
      expect(runs[0]['text'], 'Bold');
      expect(runs[0]['marks'], ['italic', 'underline', 'strikethrough']);
      expect(runs[0]['href'], '/guide');
      expect(runs[1], _headingRuns(original)[1]);
      expect(saved.body.blocks[0]['text'], 'Bold代码');
      expect(saved.body.blocks[1], original.blocks[1]);
      expect(saved.base.toJsonBlocks(), original.toJsonBlocks());
    });

    testWidgets('each supported mark changes only the chosen run', (
      tester,
    ) async {
      await _openInline(tester, h);
      for (final label in [
        'Bold',
        'Italic',
        'Underline',
        'Strikethrough',
        'Code style',
      ]) {
        await _tapRun(tester, 0, label);
      }
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs[0]['marks'], ['code']);
      expect(runs[0]['href'], '/guide');
      expect(runs[1], _headingRuns(_body())[1]);
    });

    testWidgets('a second run can be changed without touching the first', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 1, 'Code style');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs[0], _headingRuns(_body())[0]);
      expect(runs[1]['marks'], [
        'bold',
        'italic',
        'underline',
        'strikethrough',
      ]);
      expect(runs[1]['href'], 'https://external.example/path');
      expect(runs[1]['text'], '代码');
    });

    testWidgets('plain text gains explicit formatting only after an action', (
      tester,
    ) async {
      final body = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {'id': 'p', 'type': 'paragraph', 'text': 'literal **words**'},
        ],
      );
      h.reader.result = _remoteWith(body);
      await _openInline(tester, h);
      expect(
        h.session.state.body!.blocks.single.containsKey('inlines'),
        isFalse,
      );
      await _tapRun(tester, 0, 'Italic');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await h.inner.load(_key))!.body.blocks.single;
      expect(saved['text'], 'literal **words**');
      expect(saved['inlines'], [
        {
          'text': 'literal **words**',
          'marks': ['italic'],
        },
      ]);
      expect(body.blocks.single.containsKey('inlines'), isFalse);
    });

    testWidgets('a surrogate boundary across runs is refused, not repaired', (
      tester,
    ) async {
      final emoji = '😀';
      final high = emoji.substring(0, 1);
      final low = emoji.substring(1);
      final body = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'p',
            'type': 'paragraph',
            'text': 'A$high${low}B',
            'inlines': [
              {'text': 'A$high'},
              {'text': '${low}B'},
            ],
          },
        ],
      );
      h.reader.result = _remoteWith(body);
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(find.textContaining('cannot be safely edited'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), body.toJsonBlocks());
    });
  });

  group('link editing requires an explicit action', () {
    testWidgets('cancel retains original link and makes no local write', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      expect(find.text('Edit this run’s link'), findsOneWidget);
      expect(find.textContaining('not saved until you apply'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '/changed');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
      expect(_headingRuns(h.session.state.body!).first['href'], '/guide');
    });

    testWidgets('invalid link is rejected without altering the existing link', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(find.textContaining('valid site-relative'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(_headingRuns(h.session.state.body!).first['href'], '/guide');
    });

    testWidgets('applies exact valid link to only the selected run', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/new?q=one#two');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs[0]['href'], '/new?q=one#two');
      expect(runs[0]['marks'], _headingRuns(_body())[0]['marks']);
      expect(runs[1], _headingRuns(_body())[1]);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('explicit removal keeps text and mark order', (tester) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await _tapVisible(tester, find.text('Remove link locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect((runs[0] as Map).containsKey('href'), isFalse);
      expect(runs[0]['text'], 'Bold');
      expect(runs[0]['marks'], _headingRuns(_body())[0]['marks']);
      expect(runs[1], _headingRuns(_body())[1]);
    });

    testWidgets('applying the unchanged link is a no-op without a save', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(await h.inner.load(_key), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(_headingRuns(h.session.state.body!).first['href'], '/guide');
    });

    testWidgets('oversized input is rejected rather than truncated', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/safe');
      await tester.enterText(find.byType(TextField), '/${'x' * 2048}');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '/safe',
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('stale selection cannot overwrite an intervening body edit', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/stale');
      expect(
        h.session.edit(
          (body) => body.replacePlainText('paragraph', 'other edit'),
        ),
        isTrue,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(find.textContaining('text or session changed'), findsOneWidget);
      final saved = (await h.inner.load(_key))!.body;
      expect(saved.blocks[2]['text'], 'other edit');
      expect(_headingRuns(saved).first['href'], '/guide');
    });
  });

  group('identity, saving, recovery and navigation', () {
    testWidgets('account change removes visible run content immediately', (
      tester,
    ) async {
      await _openInline(tester, h);
      expect(find.text('Bold'), findsWidgets);
      expect(find.text('/guide'), findsOneWidget);
      h.identity.switchUser('other');
      await tester.pump();
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(find.text('/guide'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('account change clears a link dialog and rejects late submit', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/private-value');
      final field = tester.widget<TextField>(find.byType(TextField));
      final controller = field.controller!;
      final apply = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply link locally'),
          )
          .onPressed!;
      h.identity.switchUser('other');
      await tester.pump();
      expect(controller.text, '');
      expect(find.byType(TextField), findsNothing);
      expect(find.text('/private-value'), findsNothing);
      expect(find.textContaining('account changed'), findsWidgets);
      apply();
      await tester.pump();
      expect(await h.inner.load(_key), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('save failure remains visible and retry persists exact runs', (
      tester,
    ) async {
      h.store.failCreate = true;
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.failed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Local save failed'), findsOneWidget);
      expect(h.session.state.hasUnsavedChanges, isTrue);
      expect(await h.inner.load(_key), isNull);
      final bold = tester.widget<FilterChip>(_withinRun(0, 'Bold'));
      expect(bold.onSelected, isNull);
      h.store.failCreate = false;
      await _tapVisible(tester, find.text('Retry'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await h.inner.load(_key))!.body;
      expect(
        (_headingRuns(saved)[0]['marks'] as List).contains('bold'),
        isFalse,
      );
      expect(_headingRuns(saved)[0]['href'], '/guide');
      expect(_headingRuns(saved)[1], _headingRuns(_body())[1]);
    });

    testWidgets('back to the parent retains failed work and its exit prompt', (
      tester,
    ) async {
      h.store.failCreate = true;
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.failed);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StructuredLocalEditorPage), findsOneWidget);
      expect(h.session.state.hasUnsavedChanges, isTrue);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave with unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(h.session.state.phase, LocalStructuredPhase.saveFailed);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('competing local recovery causes conflict, not overwrite', (
      tester,
    ) async {
      await h.seed();
      final existing = (await h.inner.load(_key))!;
      h.store.hideNextLoad = true;
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.conflict);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Another local session changed'),
        findsOneWidget,
      );
      final after = (await h.inner.load(_key))!;
      expect(after.rowId, existing.rowId);
      expect(after.revision, existing.revision);
      expect(after.body.toJsonBlocks(), existing.body.toJsonBlocks());
      expect(h.session.state.hasUnsavedChanges, isTrue);
    });

    testWidgets('rapid formatting changes coalesce during a pending write', (
      tester,
    ) async {
      h.store.createGate = Completer<void>();
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(h.store.createStarted.isCompleted, isTrue);
      await _tapRun(tester, 0, 'Italic');
      await _tapRun(tester, 0, 'Code style');
      h.store.createGate!.complete();
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs[0]['marks'], ['underline', 'strikethrough', 'code']);
      expect(runs[0]['href'], '/guide');
      expect(runs[1], _headingRuns(_body())[1]);
    });

    testWidgets('background flush preserves the acknowledged format change', (
      tester,
    ) async {
      h.store.gateAfterCreate = true;
      h.store.createGate = Completer<void>();
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(h.store.createStarted.isCompleted, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      h.store.createGate!.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect((runs[0]['marks'] as List).contains('bold'), isFalse);
      expect(runs[1], _headingRuns(_body())[1]);
    });

    testWidgets('back leaves the shared session open for the parent editor', (
      tester,
    ) async {
      await _openInline(tester, h);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StructuredLocalEditorPage), findsOneWidget);
      expect(h.session.state.phase, LocalStructuredPhase.editing);
      expect(find.byTooltip('Move block down'), findsWidgets);
      expect((await h.inner.load(_key))!.body.blocks.first['text'], 'Bold代码');
    });

    testWidgets('offline local recovery is explicitly resumed before editing', (
      tester,
    ) async {
      await h.seed(body: _body());
      h.reader.result = const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
      await _open(tester, h);
      expect(find.text('Local recovery found'), findsOneWidget);
      expect(find.byTooltip('Edit text-run formatting'), findsNothing);
      await tester.tap(find.text('Resume local changes'));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byTooltip('Edit text-run formatting').first,
      );
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect((runs.first['marks'] as List).contains('bold'), isFalse);
      expect(runs[1], _headingRuns(_body())[1]);
    });
  });

  group('accessibility and bounded rendering', () {
    for (final locale in [const Locale('en'), const Locale('zh')]) {
      testWidgets('localization and semantics at large text scale $locale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await _open(tester, h, locale: locale, scale: 1.5);
          final openLabel = locale.languageCode == 'en'
              ? 'Edit text-run formatting'
              : '编辑文本片段格式';
          await _tapVisible(tester, find.byTooltip(openLabel).first);
          expect(
            find.text(
              locale.languageCode == 'en'
                  ? 'Local text-run formatting'
                  : '本地文本片段格式',
            ),
            findsOneWidget,
          );
          final mark = locale.languageCode == 'en' ? 'Bold' : '粗体';
          await tester.ensureVisible(_withinRun(0, mark));
          await tester.pumpAndSettle();
          final node = tester
              .getSemantics(_withinRun(0, mark))
              .getSemanticsData();
          expect(node.flagsCollection.isButton, isTrue);
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
      'a thousand runs are built lazily and the last remains editable',
      (tester) async {
        final body = StructuredArticleDraft.parse(
          version: 1,
          blocks: [
            {
              'id': 'p',
              'type': 'paragraph',
              'text': 'x' * 1000,
              'inlines': [
                for (var i = 0; i < 1000; i++) {'text': 'x'},
              ],
            },
          ],
        );
        h.reader.result = _remoteWith(body);
        await _openInline(tester, h);
        expect(_run(0), findsOneWidget);
        expect(_run(999), findsNothing);
        await tester.scrollUntilVisible(
          _run(999),
          1000,
          maxScrolls: 1000,
          scrollable: find.descendant(
            of: find.byType(StructuredLocalInlinePage),
            matching: find.byType(Scrollable),
          ),
        );
        await _tapVisible(tester, _withinRun(999, 'Bold'));
        expect(await h.session.flush(), LocalStructuredFlushResult.saved);
        final saved = (await h.inner.load(_key))!.body.blocks.single;
        final runs = saved['inlines'] as List;
        expect(runs, hasLength(1000));
        expect(runs.first, {'text': 'x'});
        expect(runs.last, {
          'text': 'x',
          'marks': ['bold'],
        });
        expect(saved['text'], 'x' * 1000);
      },
    );
  });
}
