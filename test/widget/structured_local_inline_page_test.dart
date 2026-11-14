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
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
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

Map<String, Object?> _listBlock(StructuredArticleDraft body) =>
    body.blocks.firstWhere((block) => block['id'] == 'list');

List<dynamic> _listRuns(StructuredArticleDraft body) =>
    _listBlock(body)['itemInlines'] as List;

StructuredArticleDraft _plainList() => StructuredArticleDraft.parse(
  version: 1,
  blocks: [
    {
      'id': 'list',
      'type': 'list',
      'ordered': false,
      'items': ['plain first', 'plain second'],
    },
  ],
);

StructuredArticleDraft _listWithLink() => StructuredArticleDraft.parse(
  version: 1,
  blocks: [
    {
      'id': 'list',
      'type': 'list',
      'ordered': false,
      'items': ['plain first', 'plain second'],
      'itemInlines': [
        [
          {'text': 'plain first'},
        ],
        [
          {
            'text': 'plain second',
            'marks': ['bold'],
            'href': '/old',
          },
        ],
      ],
    },
  ],
);

StructuredArticleDraft _reversedList(StructuredArticleDraft body) {
  final block = _listBlock(body);
  return body.replace('list', {
    ...block,
    'items': (block['items'] as List).reversed.toList(),
    'itemInlines': (block['itemInlines'] as List).reversed.toList(),
  });
}

Future<void> _openList(WidgetTester tester, _Harness h) async {
  await _open(tester, h);
  final card = find.byKey(const ValueKey<Object?>('list'));
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
  await _tapVisible(tester, action);
  expect(find.byType(StructuredLocalInlinePage), findsOneWidget);
}

Future<void> _chooseListItem(WidgetTester tester, int index) async {
  await _tapVisible(
    tester,
    find.byKey(ValueKey('structured-list-item-$index')),
  );
}

StructuredArticleDraft _rangeBody(String text) => StructuredArticleDraft.parse(
  version: 1,
  blocks: [
    {'id': 'p', 'type': 'paragraph', 'text': text},
  ],
);

Finder _rangeText() => find.byKey(const ValueKey('structured-range-text'));

Future<void> _openRange(WidgetTester tester, _Harness h) async {
  await _openInline(tester, h);
  await _tapVisible(tester, find.text('Select a text range'));
}

Future<void> _selectRange(WidgetTester tester, int base, int extent) async {
  final controller = tester.widget<TextField>(_rangeText()).controller!;
  controller.selection = TextSelection(baseOffset: base, extentOffset: extent);
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('explicit local text ranges', () {
    testWidgets('opens read-only without a selected range or a write', (
      tester,
    ) async {
      await _openRange(tester, h);
      final field = tester.widget<TextField>(_rangeText());
      expect(field.readOnly, isTrue);
      expect(field.controller!.text, 'Bold代码');
      expect(find.text('Select a nonempty text range first.'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add style locally'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Set range link'),
            )
            .onPressed,
        isNull,
      );
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('adding a mark splits a run but preserves both links', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Code style'));
      await _tapVisible(tester, find.text('Add style locally'));
      expect(
        find.textContaining('document or session changed'),
        findsOneWidget,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs.length, 4);
      expect(runs[0]['text'], 'B');
      expect(runs[1]['text'], 'ol');
      expect(runs[1]['marks'], [
        'bold',
        'italic',
        'underline',
        'strikethrough',
        'code',
      ]);
      expect(runs[1]['href'], '/guide');
      expect(runs[2]['text'], 'd');
      expect(runs[2]['marks'], _headingRuns(_body())[0]['marks']);
      expect(runs[3], _headingRuns(_body())[1]);
    });

    testWidgets(
      'removing a style across runs preserves other marks and links',
      (tester) async {
        await _openRange(tester, h);
        await _selectRange(tester, 2, 5);
        await _tapVisible(tester, find.text('Remove style locally'));
        expect(await h.session.flush(), LocalStructuredFlushResult.saved);
        final runs = _headingRuns((await h.inner.load(_key))!.body);
        expect(runs.map((r) => r['text']).toList(), ['Bo', 'ld', '代', '码']);
        expect(runs[0], {..._headingRuns(_body())[0] as Map, 'text': 'Bo'});
        expect(runs[1]['marks'], ['italic', 'underline', 'strikethrough']);
        expect(runs[1]['href'], '/guide');
        expect(runs[2]['marks'], [
          'code',
          'italic',
          'underline',
          'strikethrough',
        ]);
        expect(runs[2]['href'], 'https://external.example/path');
        expect(runs[3], {..._headingRuns(_body())[1] as Map, 'text': '码'});
      },
    );

    testWidgets('backward selection uses its normalized range', (tester) async {
      await _openRange(tester, h);
      await _selectRange(tester, 3, 1);
      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Code style'));
      await _tapVisible(tester, find.text('Add style locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs.map((r) => r['text']).toList(), ['B', 'ol', 'd', '代码']);
      expect(runs[1]['marks'], contains('code'));
      expect(runs[0]['marks'], isNot(contains('code')));
      expect(runs[2]['marks'], isNot(contains('code')));
    });

    testWidgets('collapsed selection cannot invoke any range operation', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 2, 2);
      for (final label in [
        'Add style locally',
        'Remove style locally',
        'Set range link',
        'Remove range links',
      ]) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
    });

    testWidgets('an existing style is a no-op without an unnecessary row', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      await _tapVisible(tester, find.text('Add style locally'));
      expect(find.text('No change was needed.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('structured-range-text')),
        findsOneWidget,
      );
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
    });

    testWidgets('link dialog cancel keeps the entire source unchanged', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 1, 5);
      await _tapVisible(tester, find.text('Set range link'));
      expect(find.text('Set a link for the selected range'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '/cancelled');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
    });

    testWidgets('link applies to a range crossing two existing runs', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 2, 5);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(find.byType(TextField).last, '/new');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs.map((r) => r['text']).toList(), ['Bo', 'ld', '代', '码']);
      expect(runs.map((r) => r['href']).toList(), [
        '/guide',
        '/new',
        '/new',
        'https://external.example/path',
      ]);
      expect(runs[1]['marks'], _headingRuns(_body())[0]['marks']);
      expect(runs[2]['marks'], _headingRuns(_body())[1]['marks']);
    });

    testWidgets('removing links affects only selected code units', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 3, 5);
      await _tapVisible(tester, find.text('Remove range links'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _headingRuns((await h.inner.load(_key))!.body);
      expect(runs.map((r) => r['text']).toList(), ['Bol', 'd', '代', '码']);
      expect(runs[0]['href'], '/guide');
      expect((runs[1] as Map).containsKey('href'), isFalse);
      expect((runs[2] as Map).containsKey('href'), isFalse);
      expect(runs[3]['href'], 'https://external.example/path');
      expect(runs[1]['marks'], _headingRuns(_body())[0]['marks']);
    });

    testWidgets('invalid URL keeps dialog open and source unchanged', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 0, 2);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(
        find.byType(TextField).last,
        'javascript:alert(1)',
      );
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(find.textContaining('valid site-relative'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
    });

    testWidgets('link input length limit refuses rather than truncates', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 0, 2);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(find.byType(TextField).last, '/valid');
      await tester.enterText(find.byType(TextField).last, '/${'x' * 2048}');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '/valid',
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('surrogate pair cannot be split by a selection boundary', (
      tester,
    ) async {
      final source = _rangeBody('A😀B');
      h.reader.result = _remoteWith(source);
      await _openRange(tester, h);
      await _selectRange(tester, 0, 2);
      await _tapVisible(tester, find.text('Remove style locally'));
      expect(find.textContaining('cannot be applied safely'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), source.toJsonBlocks());
    });

    testWidgets(
      'a complete surrogate pair can be selected without corruption',
      (tester) async {
        final source = _rangeBody('A😀B');
        h.reader.result = _remoteWith(source);
        await _openRange(tester, h);
        await _selectRange(tester, 1, 3);
        await _tapVisible(tester, find.text('Add style locally'));
        expect(await h.session.flush(), LocalStructuredFlushResult.saved);
        final block = (await h.inner.load(_key))!.body.blocks.single;
        expect(block['text'], 'A😀B');
        expect(block['inlines'], [
          {'text': 'A'},
          {
            'text': '😀',
            'marks': ['bold'],
          },
          {'text': 'B'},
        ]);
      },
    );

    testWidgets('malformed fallback never enters the selection renderer', (
      tester,
    ) async {
      final source = _rangeBody('bad${'😀'.substring(0, 1)}');
      h.reader.result = _remoteWith(source);
      await _openRange(tester, h);
      expect(find.byKey(const ValueKey('structured-range-text')), findsNothing);
      expect(
        find.textContaining('document or session changed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), source.toJsonBlocks());
    });

    testWidgets('selection is invalidated by any other body edit', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      final old = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Remove style locally'),
          )
          .onPressed!;
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      old();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('structured-range-text')), findsNothing);
      expect(
        find.textContaining('document or session changed'),
        findsOneWidget,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _headingRuns((await h.inner.load(_key))!.body),
        _headingRuns(_body()),
      );
    });

    testWidgets('changed then restored body never revives a stale selection', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      final callback = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Remove style locally'),
          )
          .onPressed!;
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      expect(h.session.edit((body) => body.move('image-two', 5)), isTrue);
      callback();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('document or session changed'),
        findsOneWidget,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _headingRuns((await h.inner.load(_key))!.body),
        _headingRuns(_body()),
      );
    });

    testWidgets(
      'account switch hides selected content and blocks old callbacks',
      (tester) async {
        await _openRange(tester, h);
        await _selectRange(tester, 1, 3);
        final callback = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove style locally'),
            )
            .onPressed!;
        h.identity.switchUser('other');
        callback();
        await tester.pump();
        expect(find.textContaining('account changed'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('structured-range-text')),
          findsNothing,
        );
        expect(find.text('Bold代码'), findsNothing);
        expect(await h.inner.load(_key), isNull);
      },
    );

    testWidgets('identity change clears pending range link input', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 0, 3);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(find.byType(TextField).last, '/private');
      h.identity.switchUser(null);
      await tester.pump();
      expect(find.text('/private'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('account changed'), findsWidgets);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('body changes while dialog is open disable confirmation', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 0, 3);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(find.byType(TextField).last, '/stale');
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('/stale'), findsNothing);
      expect(find.textContaining('document or session changed'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply link locally'),
            )
            .onPressed,
        isNull,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _headingRuns((await h.inner.load(_key))!.body),
        _headingRuns(_body()),
      );
    });

    testWidgets('change and restoration while dialog is open stay stale', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 0, 3);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(find.byType(TextField).last, '/stale');
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      expect(h.session.edit((body) => body.move('image-two', 5)), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply link locally'),
            )
            .onPressed,
        isNull,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _headingRuns((await h.inner.load(_key))!.body),
        _headingRuns(_body()),
      );
    });

    testWidgets('plain list range only promotes on an actual edit', (
      tester,
    ) async {
      final source = _plainList();
      h.reader.result = _remoteWith(source);
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapVisible(tester, find.text('Select a text range'));
      await _selectRange(tester, 6, 12);
      await _tapVisible(tester, find.text('Add style locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final block = _listBlock((await h.inner.load(_key))!.body);
      expect(block['items'], ['plain first', 'plain second']);
      expect(block['itemInlines'], [
        [
          {'text': 'plain first'},
        ],
        [
          {'text': 'plain '},
          {
            'text': 'second',
            'marks': ['bold'],
          },
        ],
      ]);
      expect(_listBlock(source).containsKey('itemInlines'), isFalse);
    });

    testWidgets('list item reorder prevents old range callback from applying', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapVisible(tester, find.text('Select a text range'));
      await _selectRange(tester, 1, 4);
      final callback = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Remove style locally'),
          )
          .onPressed!;
      expect(h.session.edit(_reversedList), isTrue);
      callback();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('document or session changed'),
        findsOneWidget,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _listRuns((await h.inner.load(_key))!.body),
        _listRuns(_reversedList(_body())),
      );
    });

    testWidgets('local storage failure retains the accepted range edit', (
      tester,
    ) async {
      h.store.failCreate = true;
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      await _tapVisible(tester, find.text('Remove style locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.failed);
      await tester.pumpAndSettle();
      expect(h.session.state.hasUnsavedChanges, isTrue);
      expect(await h.inner.load(_key), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Local save failed'), findsOneWidget);
      h.store.failCreate = false;
      await _tapVisible(tester, find.text('Retry'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(_headingRuns((await h.inner.load(_key))!.body)[1]['text'], 'ol');
    });

    testWidgets('competing local recovery is never overwritten', (
      tester,
    ) async {
      await h.seed();
      final before = (await h.inner.load(_key))!;
      h.store.hideNextLoad = true;
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      await _tapVisible(tester, find.text('Remove style locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.conflict);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Another local session changed'),
        findsOneWidget,
      );
      final after = (await h.inner.load(_key))!;
      expect(after.rowId, before.rowId);
      expect(after.revision, before.revision);
      expect(after.body.toJsonBlocks(), before.body.toJsonBlocks());
    });

    testWidgets('body change before range route builds discards its seed', (
      tester,
    ) async {
      await _openInline(tester, h);
      await tester.ensureVisible(find.text('Select a text range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a text range'));
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('structured-range-text')), findsNothing);
      expect(
        find.textContaining('document or session changed'),
        findsOneWidget,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _headingRuns((await h.inner.load(_key))!.body),
        _headingRuns(_body()),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('body change before link dialog builds discards its seed', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      await tester.ensureVisible(find.text('Set range link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set range link'));
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply link locally'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('document or session changed'), findsWidgets);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _headingRuns((await h.inner.load(_key))!.body),
        _headingRuns(_body()),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'account change before range route builds does not adopt the seed',
      (tester) async {
        await _openInline(tester, h);
        await tester.ensureVisible(find.text('Select a text range'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select a text range'));
        h.identity.switchUser('other');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('structured-range-text')),
          findsNothing,
        );
        expect(find.textContaining('account changed'), findsWidgets);
        expect(await h.inner.load(_key), isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('account change before link dialog builds discards seed', (
      tester,
    ) async {
      await _openRange(tester, h);
      await _selectRange(tester, 0, 3);
      await tester.ensureVisible(find.text('Set range link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set range link'));
      h.identity.switchUser('other');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('account changed'), findsWidgets);
      expect(await h.inner.load(_key), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing nonexistent links does not promote a plain block', (
      tester,
    ) async {
      final source = _rangeBody('plain text');
      h.reader.result = _remoteWith(source);
      await _openRange(tester, h);
      await _selectRange(tester, 1, 5);
      await _tapVisible(tester, find.text('Remove range links'));
      expect(find.text('No change was needed.'), findsOneWidget);
      expect(
        h.session.state.body!.blocks.single.containsKey('inlines'),
        isFalse,
      );
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('too many resulting runs are rejected without merging', (
      tester,
    ) async {
      final source = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'p',
            'type': 'paragraph',
            'text': 'aa${'x' * 999}',
            'inlines': [
              {'text': 'aa'},
              for (var i = 0; i < 999; i++) {'text': 'x'},
            ],
          },
        ],
      );
      h.reader.result = _remoteWith(source);
      await _openRange(tester, h);
      await _selectRange(tester, 0, 1);
      await _tapVisible(tester, find.text('Add style locally'));
      expect(find.textContaining('cannot be applied safely'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), source.toJsonBlocks());
    });

    testWidgets('link splitting past the run limit reports a safe failure', (
      tester,
    ) async {
      final source = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'p',
            'type': 'paragraph',
            'text': 'aa${'x' * 999}',
            'inlines': [
              {'text': 'aa'},
              for (var i = 0; i < 999; i++) {'text': 'x'},
            ],
          },
        ],
      );
      h.reader.result = _remoteWith(source);
      await _openRange(tester, h);
      await _selectRange(tester, 0, 1);
      await _tapVisible(tester, find.text('Set range link'));
      await tester.enterText(find.byType(TextField).last, '/valid');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(find.textContaining('cannot be applied safely'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), source.toJsonBlocks());
    });

    testWidgets(
      'changed displayed text cannot redirect offsets into the body',
      (tester) async {
        await _openRange(tester, h);
        final controller = tester.widget<TextField>(_rangeText()).controller!;
        controller.value = const TextEditingValue(
          text: 'fake text',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        );
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('Remove style locally'));
        expect(find.textContaining('cannot be applied safely'), findsOneWidget);
        expect(await h.inner.load(_key), isNull);
        expect(h.session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
      },
    );

    testWidgets('background flush persists an accepted range operation', (
      tester,
    ) async {
      h.store.gateAfterCreate = true;
      h.store.createGate = Completer<void>();
      await _openRange(tester, h);
      await _selectRange(tester, 1, 3);
      await _tapVisible(tester, find.text('Remove style locally'));
      expect(h.store.createStarted.isCompleted, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      h.store.createGate!.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(_headingRuns((await h.inner.load(_key))!.body)[1]['text'], 'ol');
    });

    testWidgets('Chinese selection surface uses localized controls', (
      tester,
    ) async {
      h.reader.result = _remoteWith(_rangeBody('文本内容'));
      await _open(tester, h, locale: const Locale('zh'));
      await _tapVisible(tester, find.byTooltip('编辑文本片段格式'));
      await _tapVisible(tester, find.text('选择文本范围'));
      expect(find.text('本地范围格式'), findsOneWidget);
      expect(find.text('请先选择非空文本范围。'), findsOneWidget);
      await _selectRange(tester, 0, 2);
      await _tapVisible(tester, find.text('在本地添加样式'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect((await h.inner.load(_key))!.body.blocks.single['text'], '文本内容');
    });
  });

  group('list-item formatting', () {
    testWidgets('opening the list requires an explicit item choice', (
      tester,
    ) async {
      await _openList(tester, h);
      expect(find.text('List item 1'), findsOneWidget);
      expect(find.text('List item 2'), findsOneWidget);
      expect(find.text('First item'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), _body().toJsonBlocks());
    });

    testWidgets('selecting first item exposes only its runs', (tester) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      expect(find.text('Selected list item 1'), findsOneWidget);
      expect(find.text('First '), findsOneWidget);
      expect(find.text('item'), findsOneWidget);
      expect(find.text(' second item '), findsNothing);
      expect(find.byType(FilterChip), findsWidgets);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('selecting second item does not expose first runs', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      expect(find.text('Selected list item 2'), findsOneWidget);
      expect(find.text(' second item '), findsOneWidget);
      expect(find.text('First '), findsNothing);
      expect(find.text('item'), findsNothing);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('choosing a different item does not create recovery', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapVisible(tester, find.text('Choose a different list item'));
      expect(find.text('List item 2'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      await _chooseListItem(tester, 1);
      expect(find.text('Selected list item 2'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('marking one run preserves every other item and block', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 1, 'Italic');
      expect(find.text('List item 1'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final saved = (await h.inner.load(_key))!.body;
      final runs = _listRuns(saved);
      expect(runs[0][0], _listRuns(_body())[0][0]);
      expect(runs[0][1], {
        'text': 'item',
        'marks': ['italic'],
      });
      expect(runs[1], _listRuns(_body())[1]);
      expect(_listBlock(saved)['items'], _listBlock(_body())['items']);
      expect(
        saved.blocks.where((b) => b['id'] != 'list').toList(),
        _body().blocks.where((b) => b['id'] != 'list').toList(),
      );
    });

    testWidgets('marking second item leaves first item intact', (tester) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _listRuns((await h.inner.load(_key))!.body);
      expect(runs[0], _listRuns(_body())[0]);
      expect(runs[1][0]['text'], ' second item ');
      expect(runs[1][0]['marks'], ['underline', 'bold']);
    });

    testWidgets('removing an existing mark keeps other runs unchanged', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _listRuns((await h.inner.load(_key))!.body);
      expect(runs[0][0]['text'], 'First ');
      expect(runs[0][0]['marks'], isEmpty);
      expect(runs[0][1], _listRuns(_body())[0][1]);
      expect(runs[1], _listRuns(_body())[1]);
    });

    testWidgets('a fresh choice is required for every changed snapshot', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Italic');
      expect(find.byType(FilterChip), findsNothing);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Underline');
      expect(find.byType(FilterChip), findsNothing);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(_listRuns((await h.inner.load(_key))!.body)[0][0]['marks'], [
        'bold',
        'italic',
        'underline',
      ]);
    });

    testWidgets('a plain list is not promoted on selection or cancel', (
      tester,
    ) async {
      final body = _plainList();
      h.reader.result = _remoteWith(body);
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      expect(
        _listBlock(h.session.state.body!).containsKey('itemInlines'),
        isFalse,
      );
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/not-applied');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
      expect(
        _listBlock(h.session.state.body!).containsKey('itemInlines'),
        isFalse,
      );
    });

    testWidgets('a plain list promotes all item runs only after change', (
      tester,
    ) async {
      final body = _plainList();
      h.reader.result = _remoteWith(body);
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapRun(tester, 0, 'Code style');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final list = _listBlock((await h.inner.load(_key))!.body);
      expect(list['items'], ['plain first', 'plain second']);
      expect(list['itemInlines'], [
        [
          {'text': 'plain first'},
        ],
        [
          {
            'text': 'plain second',
            'marks': ['code'],
          },
        ],
      ]);
      expect(_listBlock(body).containsKey('itemInlines'), isFalse);
    });

    testWidgets('link cancel preserves original and makes no write', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/cancelled');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await h.inner.load(_key), isNull);
      expect(_listRuns(h.session.state.body!), _listRuns(_body()));
      expect(find.text('Selected list item 1'), findsOneWidget);
    });

    testWidgets('link applies only to the chosen run', (tester) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 1, 'Edit link');
      await tester.enterText(find.byType(TextField), '/local-guide');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _listRuns((await h.inner.load(_key))!.body);
      expect(runs[0][0], _listRuns(_body())[0][0]);
      expect(runs[0][1], {'text': 'item', 'href': '/local-guide'});
      expect(runs[1], _listRuns(_body())[1]);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('invalid link is rejected without any list mutation', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(find.byType(TextField), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
      expect(_listRuns(h.session.state.body!), _listRuns(_body()));
    });

    testWidgets('removing a link preserves marks and other items', (
      tester,
    ) async {
      final source = _listWithLink();
      h.reader.result = _remoteWith(source);
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapRun(tester, 0, 'Edit link');
      await _tapVisible(tester, find.text('Remove link locally'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final runs = _listRuns((await h.inner.load(_key))!.body);
      expect(runs[0], _listRuns(source)[0]);
      expect(runs[1][0], {
        'text': 'plain second',
        'marks': ['bold'],
      });
    });

    testWidgets('unchanged link is a no-op and keeps current selection', (
      tester,
    ) async {
      final source = _listWithLink();
      h.reader.result = _remoteWith(source);
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapRun(tester, 0, 'Edit link');
      await _tapVisible(tester, find.text('Apply link locally'));
      expect(await h.inner.load(_key), isNull);
      expect(find.text('Selected list item 2'), findsOneWidget);
      expect(_listRuns(h.session.state.body!), _listRuns(source));
    });

    testWidgets('reordering items clears selected index before another tap', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      expect(h.session.edit(_reversedList), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Selected list item 1'), findsNothing);
      expect(find.text(' second item '), findsOneWidget);
      await _chooseListItem(tester, 0);
      expect(find.text(' second item '), findsOneWidget);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _listRuns((await h.inner.load(_key))!.body),
        _listRuns(_reversedList(_body())),
      );
    });

    testWidgets('unrelated body changes also require a fresh choice', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      expect(h.session.edit((body) => body.move('image-two', 1)), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('List item 1'), findsOneWidget);
      await _chooseListItem(tester, 1);
      expect(find.text('Selected list item 2'), findsOneWidget);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(_listRuns((await h.inner.load(_key))!.body), _listRuns(_body()));
    });

    testWidgets('a stale dialog cannot apply after a list reorder', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/stale');
      expect(h.session.edit(_reversedList), isTrue);
      await tester.pumpAndSettle();
      expect(find.textContaining('text or session changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply link locally'),
            )
            .onPressed,
        isNull,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _listRuns((await h.inner.load(_key))!.body),
        _listRuns(_reversedList(_body())),
      );
    });

    testWidgets('a changed then restored list never revives a dialog', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/stale');
      expect(h.session.edit(_reversedList), isTrue);
      expect(h.session.edit(_reversedList), isTrue);
      await tester.pumpAndSettle();
      expect(find.textContaining('text or session changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply link locally'),
            )
            .onPressed,
        isNull,
      );
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(_listRuns((await h.inner.load(_key))!.body), _listRuns(_body()));
    });

    testWidgets('deleting the chosen list makes the screen unsupported', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      expect(h.session.edit((body) => body.remove('list')), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('cannot be safely edited'), findsOneWidget);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        (await h.inner.load(_key))!.body.blocks.any((b) => b['id'] == 'list'),
        isFalse,
      );
    });

    testWidgets('identity change clears selected item content', (tester) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      h.identity.switchUser('other');
      await tester.pump();
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(find.text('First '), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('identity change clears an open list link field', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      await _tapRun(tester, 0, 'Edit link');
      await tester.enterText(find.byType(TextField), '/private');
      h.identity.switchUser(null);
      await tester.pump();
      expect(find.text('/private'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('account changed'), findsWidgets);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('malformed item text is hidden and disabled', (tester) async {
      final high = '😀'.substring(0, 1);
      final source = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'list',
            'type': 'list',
            'ordered': false,
            'items': ['bad$high', 'safe'],
          },
        ],
      );
      h.reader.result = _remoteWith(source);
      await _openList(tester, h);
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey('structured-list-item-0')),
      );
      expect(tile.onTap, isNull);
      expect(find.textContaining('cannot be safely edited'), findsWidgets);
      await _chooseListItem(tester, 1);
      expect(find.text('safe'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('split surrogate runs are hidden without altering the list', (
      tester,
    ) async {
      final emoji = '😀';
      final high = emoji.substring(0, 1);
      final low = emoji.substring(1);
      final source = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'list',
            'type': 'list',
            'ordered': false,
            'items': ['A$high${low}B'],
            'itemInlines': [
              [
                {'text': 'A$high'},
                {'text': '${low}B'},
              ],
            ],
          },
        ],
      );
      h.reader.result = _remoteWith(source);
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      expect(
        tester.widget<FilterChip>(_withinRun(0, 'Bold')).onSelected,
        isNull,
      );
      expect(
        tester.widget<FilterChip>(_withinRun(1, 'Bold')).onSelected,
        isNull,
      );
      expect(tester.takeException(), isNull);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), source.toJsonBlocks());
    });

    testWidgets('save failure leaves edits in memory and offers retry', (
      tester,
    ) async {
      h.store.failCreate = true;
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.failed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Local save failed'), findsOneWidget);
      expect(h.session.state.hasUnsavedChanges, isTrue);
      expect(await h.inner.load(_key), isNull);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('structured-list-item-0')),
            )
            .onTap,
        isNull,
      );
      h.store.failCreate = false;
      await _tapVisible(tester, find.text('Retry'));
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(_listRuns((await h.inner.load(_key))!.body)[1][0]['marks'], [
        'underline',
        'bold',
      ]);
      await tester.pumpAndSettle();
      await _chooseListItem(tester, 1);
      expect(find.text('Selected list item 2'), findsOneWidget);
    });

    testWidgets('competing recovery causes conflict and is never overwritten', (
      tester,
    ) async {
      await h.seed();
      final existing = (await h.inner.load(_key))!;
      h.store.hideNextLoad = true;
      await _openList(tester, h);
      await _chooseListItem(tester, 1);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.conflict);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Another local session changed'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('structured-list-item-0')),
            )
            .onTap,
        isNull,
      );
      expect(
        (await h.inner.load(_key))!.body.toJsonBlocks(),
        existing.body.toJsonBlocks(),
      );
    });

    testWidgets('stale callback cannot target a newly reordered item', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      final callback = tester
          .widget<FilterChip>(_withinRun(0, 'Italic'))
          .onSelected!;
      expect(h.session.edit(_reversedList), isTrue);
      callback(true);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      expect(
        _listRuns((await h.inner.load(_key))!.body),
        _listRuns(_reversedList(_body())),
      );
    });

    testWidgets('stale callback cannot act after identity change', (
      tester,
    ) async {
      await _openList(tester, h);
      await _chooseListItem(tester, 0);
      final callback = tester
          .widget<FilterChip>(_withinRun(0, 'Italic'))
          .onSelected!;
      h.identity.switchUser('other');
      callback(true);
      await tester.pump();
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
    });

    testWidgets('large list uses lazy item selection and preserves order', (
      tester,
    ) async {
      final source = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {
            'id': 'list',
            'type': 'list',
            'ordered': true,
            'items': [for (var i = 0; i < 100; i++) 'item $i'],
          },
        ],
      );
      h.reader.result = _remoteWith(source);
      await _openList(tester, h);
      final last = find.byKey(const ValueKey('structured-list-item-99'));
      expect(last, findsNothing);
      await tester.scrollUntilVisible(
        last,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await _tapVisible(tester, last);
      expect(find.text('Selected list item 100'), findsOneWidget);
      await _tapRun(tester, 0, 'Bold');
      expect(await h.session.flush(), LocalStructuredFlushResult.saved);
      final block = _listBlock((await h.inner.load(_key))!.body);
      expect(block['items'], _listBlock(source)['items']);
      final runs = block['itemInlines'] as List;
      expect(runs.length, 100);
      expect(runs.first, [
        {'text': 'item 0'},
      ]);
      expect(runs.last, [
        {
          'text': 'item 99',
          'marks': ['bold'],
        },
      ]);
    });

    testWidgets('Chinese list instructions and actions are localized', (
      tester,
    ) async {
      h.reader.result = _remoteWith(_plainList());
      await _open(tester, h, locale: const Locale('zh'));
      await _tapVisible(tester, find.byTooltip('编辑文本片段格式'));
      expect(find.text('列表项目 1'), findsOneWidget);
      expect(find.textContaining('没有稳定 ID'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('structured-list-item-0')),
      );
      expect(find.text('已选择列表项目 1'), findsOneWidget);
      expect(find.text('选择其他列表项目'), findsOneWidget);
      expect(await h.inner.load(_key), isNull);
    });
  });

  group('entry and exact run formatting', () {
    testWidgets('v1 text and list blocks expose formatting, not images', (
      tester,
    ) async {
      await _open(tester, h);
      for (final id in ['heading', 'image-one', 'paragraph', 'quote', 'list']) {
        final card = find.byKey(ValueKey<Object?>(id));
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
          ['heading', 'paragraph', 'quote', 'list'].contains(id)
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
      final unsafe = find.descendant(
        of: _run(0),
        matching: find.textContaining('cannot be safely edited'),
      );
      expect(unsafe, findsOneWidget);
      final bold = tester.widget<FilterChip>(_withinRun(0, 'Bold'));
      expect(bold.onSelected, isNull);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), body.toJsonBlocks());
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'unpaired fallback is hidden rather than sent to the text renderer',
    (tester) async {
      final high = '😀'.substring(0, 1);
      final body = StructuredArticleDraft.parse(
        version: 1,
        blocks: [
          {'id': 'p', 'type': 'paragraph', 'text': 'broken$high'},
        ],
      );
      h.reader.result = _remoteWith(body);
      await _open(tester, h);
      expect(find.textContaining('cannot be safely edited'), findsOneWidget);
      await _tapVisible(tester, find.byTooltip('Edit text-run formatting'));
      expect(find.textContaining('cannot be safely edited'), findsOneWidget);
      expect(
        tester.widget<FilterChip>(_withinRun(0, 'Bold')).onSelected,
        isNull,
      );
      expect(tester.takeException(), isNull);
      expect(await h.inner.load(_key), isNull);
      expect(h.session.state.body!.toJsonBlocks(), body.toJsonBlocks());
    },
  );

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

    testWidgets(
      'identity change before dialog construction does not adopt its seed',
      (tester) async {
        await _openInline(tester, h);
        await tester.ensureVisible(_withinRun(0, 'Edit link'));
        await tester.pumpAndSettle();
        await tester.tap(_withinRun(0, 'Edit link'));
        h.identity.switchUser('other');
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('/guide'), findsNothing);
        expect(find.textContaining('account changed'), findsWidgets);
        expect(await h.inner.load(_key), isNull);
        expect(tester.takeException(), isNull);
      },
    );

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
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
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
