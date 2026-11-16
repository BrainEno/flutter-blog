import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/local_structured_rich_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_rich_text_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/structured_article_fixtures.dart';

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article-id',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 1);
final _time = DateTime.utc(2026);

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
  void change() {
    activeUserId = 'other';
    sessionGeneration++;
    events.add(null);
  }
}

class _Harness {
  _Harness() {
    db = AppDatabase(NativeDatabase.memory());
    store = SqliteStructuredBodyRecoveryStore(
      db,
      apiBaseUrl: Uri.parse('https://example.invalid'),
    );
  }
  late AppDatabase db;
  late SqliteStructuredBodyRecoveryStore store;
  final identity = _Identity();
  LocalStructuredRichTextSession? session;
  Future<LocalStructuredRichTextSession> create({
    bool composing = false,
  }) async {
    final article = structuredArticle();
    final body = StructuredArticleDraft.parse(
      version: article['contentBlocksVersion'],
      blocks: article['contentBlocks'],
    );
    final parent = (await store.create(
      key: _key,
      base: body,
      body: body,
      updatedAt: _time,
    ))!;
    final saved = composing
        ? await store.createRichTextBuffer(
            expected: parent,
            buffer: StructuredRichTextBuffer(
              blockId: 'heading',
              itemIndex: null,
              runs: [
                StructuredRichBufferRun(
                  text: 'unfinished',
                  marks: ['bold'],
                  href: '/guide',
                ),
              ],
              selectionBase: 2,
              selectionExtent: 2,
              composingStart: 0,
              composingEnd: 2,
            ),
            updatedAt: _time,
          )
        : null;
    return session = LocalStructuredRichTextSession(
      key: _key,
      selectedRowId: parent.rowId,
      blockId: 'heading',
      itemIndex: null,
      fence: _fence,
      identity: identity,
      store: store,
      expectedUnbufferedParent: saved == null ? parent : null,
      expectedBufferedRecovery: saved,
      now: () => _time,
    );
  }

  Future<void> dispose() async {
    await session?.close(abandonUnsaved: true);
    await identity.events.close();
    await db.close();
  }
}

Future<void> _show(
  WidgetTester tester,
  LocalStructuredRichTextSession session,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StructuredLocalRichTextPage(session: session),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  for (
    var i = 0;
    i < 50 && session.state.phase == LocalRichTextPhase.opening;
    i++
  ) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  testWidgets(
    'explicit resume, one run input, local apply retains other runs',
    (tester) async {
      final session = await h.create();
      await _show(tester, session);
      expect(session.state.phase, LocalRichTextPhase.recoveryChoice);
      await _tap(tester, find.text('Continue local text'));
      await _tap(tester, find.byKey(const ValueKey('structured-rich-run-0')));
      await tester.enterText(find.byType(TextField), 'New');
      await tester.pumpAndSettle();
      expect(await session.flush(), LocalRichTextFlushResult.saved);
      final saved = await h.store.loadRichTextBuffer(_key);
      expect(saved!.buffer.runs.first.text, 'New');
      expect(saved.buffer.runs.first.href, '/guide');
      expect(saved.buffer.runs.last.text, '代码');
      await _tap(tester, find.text('Apply to local body'));
      await _tap(tester, find.text('Apply to local body').last);
      await tester.pumpAndSettle();
      final row = await h.store.load(_key);
      expect(row!.body.blocks.first['text'], 'New代码');
      expect(row.body.blocks[1]['alt'], 'First image alt');
    },
  );

  testWidgets('recovered composition requires a separate explicit choice', (
    tester,
  ) async {
    final session = await h.create(composing: true);
    await _show(tester, session);
    await _tap(tester, find.text('Continue local text'));
    expect(find.textContaining('unfinished composition'), findsOneWidget);
    await _tap(tester, find.text('Clear composition marker'));
    await _tap(tester, find.text('Cancel').last);
    expect(session.state.buffer!.composingEnd, 2);
    await _tap(tester, find.text('Clear composition marker'));
    await _tap(tester, find.text('Clear composition marker').last);
    expect(session.state.buffer!.composingEnd, -1);
    expect(session.state.buffer!.runs.first.text, 'unfinished');
  });

  testWidgets('account change clears the previous input immediately', (
    tester,
  ) async {
    final session = await h.create();
    await _show(tester, session);
    await _tap(tester, find.text('Continue local text'));
    await _tap(tester, find.byKey(const ValueKey('structured-rich-run-0')));
    h.identity.change();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Bold'), findsNothing);
    expect(session.state.phase, LocalRichTextPhase.invalidated);
  });
}
