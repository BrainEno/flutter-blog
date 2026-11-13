import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_editor_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_recovery_catalog_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Identity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'alice';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 2;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get identityChanges => events.stream;
  void change(String user) {
    activeUserId = user;
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
    throw StateError('Should never contact network');
  }
}

class _Catalog implements StructuredRecoveryCatalog {
  _Catalog(this.inner);
  final StructuredRecoveryCatalog inner;
  bool fail = false;
  Completer<StructuredRecoveryIndexPage>? gate;
  int calls = 0;
  @override
  Future<StructuredRecoveryIndexPage> page({
    required String userId,
    int? afterRowId,
  }) async {
    calls++;
    if (fail) throw StateError('disk error');
    if (gate != null) return gate!.future;
    return inner.page(userId: userId, afterRowId: afterRowId);
  }
}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
  updatedAt: DateTime.utc(2026),
);
StructuredBodyKey _key(
  String id, {
  String user = 'alice',
  String locale = 'en',
}) => StructuredBodyKey(userId: user, articleId: id, locale: locale);
StructuredArticleDraft _body(String value) => StructuredArticleDraft.parse(
  version: 0,
  blocks: [
    {'id': 'p', 'type': 'paragraph', 'text': value},
    {'id': 'q', 'type': 'quote', 'text': 'quoted'},
  ],
);

class _Harness {
  _Harness() {
    db = AppDatabase(NativeDatabase.memory());
    store = SqliteStructuredBodyRecoveryStore(
      db,
      apiBaseUrl: Uri.parse('https://catalog.invalid'),
    );
    identity = _Identity();
    reader = _Reader();
    catalog = _Catalog(store);
    user = AppUserCubit()..updateUser(_user('alice'));
    list = ListStructuredRecoveries(catalog: catalog, identity: identity);
    opener = OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    );
  }
  late AppDatabase db;
  late SqliteStructuredBodyRecoveryStore store;
  late _Identity identity;
  late _Reader reader;
  late _Catalog catalog;
  late AppUserCubit user;
  late ListStructuredRecoveries list;
  late OpenStructuredEditingSession opener;
  final fence = const NowaveSessionFence(userId: 'alice', generation: 2);

  Future<StructuredBodyRecovery> seed(
    String article, {
    String account = 'alice',
    String locale = 'en',
  }) async => (await store.create(
    key: _key(article, user: account, locale: locale),
    base: _body('base'),
    body: _body('local body'),
    updatedAt: DateTime.utc(2026),
  ))!;

  Future<void> pump(
    WidgetTester tester, {
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
        home: StructuredRecoveryCatalogPage(
          list: list,
          opener: opener,
          user: user,
          fence: fence,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    if (catalog.gate != null && !catalog.gate!.isCompleted) {
      catalog.gate!.complete(
        StructuredRecoveryIndexPage(entries: [], nextCursor: null),
      );
    }
    await identity.events.close();
    await user.close();
    await db.close();
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() async => h.dispose());

  testWidgets(
    'empty local index is distinct from remote article list and publish',
    (tester) async {
      await h.pump(tester);
      expect(find.text('Local recoveries'), findsOneWidget);
      expect(find.textContaining('No local recoveries'), findsOneWidget);
      expect(find.textContaining('nothing is published'), findsOneWidget);
      expect(find.text('Publish'), findsNothing);
      expect(h.reader.calls, 0);
    },
  );

  testWidgets(
    'current account rows and exact editions are shown without bodies',
    (tester) async {
      await h.seed('work-en');
      await h.seed('work-tw', locale: 'zh-TW');
      await h.seed('bob-private', account: 'bob');
      await h.pump(tester);
      expect(find.text('work-en'), findsOneWidget);
      expect(find.text('work-tw'), findsOneWidget);
      expect(find.text('bob-private'), findsNothing);
      expect(find.text('local body'), findsNothing);
      expect(find.textContaining('English'), findsOneWidget);
      expect(find.textContaining('Chinese (Traditional)'), findsOneWidget);
      expect(h.reader.calls, 0);
    },
  );

  testWidgets('opening offline recovery asks first and never contacts reader', (
    tester,
  ) async {
    await h.seed('work-one');
    await h.pump(tester);
    await tester.tap(find.text('work-one'));
    await tester.pumpAndSettle();
    expect(find.byType(StructuredLocalEditorPage), findsOneWidget);
    expect(find.text('Local recovery found'), findsOneWidget);
    expect(find.textContaining('could not be fully compared'), findsOneWidget);
    expect(find.text('local body'), findsNothing);
    await tester.tap(find.text('Resume local changes'));
    await tester.pumpAndSettle();
    expect(find.text('local body'), findsOneWidget);
    expect(find.text('Publish'), findsNothing);
    expect(h.reader.calls, 0);
  });

  testWidgets('failed list offers retry and retains all rows', (tester) async {
    await h.seed('work-one');
    h.catalog.fail = true;
    await h.pump(tester);
    expect(
      find.textContaining('Could not read local recoveries'),
      findsOneWidget,
    );
    expect(find.text('work-one'), findsNothing);
    expect(
      (await h.store.load(_key('work-one')))!.body.blocks.first['text'],
      'local body',
    );
    h.catalog.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('work-one'), findsOneWidget);
    expect(h.reader.calls, 0);
  });

  testWidgets('invalid identity is shown but cannot be opened or deleted', (
    tester,
  ) async {
    await h.seed('broken');
    await h.db.customStatement(
      "UPDATE structured_body_drafts SET locale = 'unsupported'",
    );
    await h.pump(tester);
    expect(find.text('Unrecognized local record'), findsOneWidget);
    expect(find.textContaining('has not been deleted'), findsOneWidget);
    expect(find.text('broken'), findsNothing);
    await tester.tap(find.text('Unrecognized local record'));
    await tester.pumpAndSettle();
    expect(find.byType(StructuredLocalEditorPage), findsNothing);
    expect(
      (await h.db.customSelect('SELECT id FROM structured_body_drafts').get()),
      hasLength(1),
    );
  });

  testWidgets('account change immediately hides listed identities', (
    tester,
  ) async {
    await h.seed('alice-private');
    await h.pump(tester);
    expect(find.text('alice-private'), findsOneWidget);
    h.identity.change('bob');
    await tester.pump();
    expect(find.text('alice-private'), findsNothing);
    expect(find.textContaining('account changed'), findsOneWidget);
    expect(
      (await h.store.load(_key('alice-private')))!.body.blocks.first['text'],
      'local body',
    );
  });

  testWidgets(
    'app user changes hide content even if identity notification is late',
    (tester) async {
      await h.seed('alice-private');
      await h.pump(tester);
      h.user.updateUser(_user('bob'));
      await tester.pump();
      expect(find.text('alice-private'), findsNothing);
      expect(find.textContaining('account changed'), findsOneWidget);
      h.user.updateUser(_user('alice'));
      await tester.pump();
      expect(find.text('alice-private'), findsNothing);
    },
  );

  testWidgets('late catalog completion cannot reveal a previous account', (
    tester,
  ) async {
    await h.seed('alice-private');
    final page = await h.store.page(userId: 'alice');
    h.catalog.gate = Completer<StructuredRecoveryIndexPage>();
    await h.pump(tester);
    expect(find.textContaining('Loading local recoveries'), findsOneWidget);
    h.identity.change('bob');
    h.catalog.gate!.complete(page);
    await tester.pumpAndSettle();
    expect(find.text('alice-private'), findsNothing);
    expect(find.textContaining('account changed'), findsOneWidget);
  });

  testWidgets('app account change hides an already open offline editor', (
    tester,
  ) async {
    await h.seed('work-one');
    await h.pump(tester);
    await tester.tap(find.text('work-one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume local changes'));
    await tester.pumpAndSettle();
    expect(find.text('local body'), findsOneWidget);
    h.user.updateUser(_user('bob'));
    await tester.pump();
    expect(find.text('local body'), findsNothing);
    expect(find.textContaining('account changed'), findsOneWidget);
    expect(
      (await h.store.load(_key('work-one')))!.body.blocks.first['text'],
      'local body',
    );
    expect(h.reader.calls, 0);
  });

  testWidgets('deleted and recreated selection is not silently resumed', (
    tester,
  ) async {
    final old = await h.seed('work-one');
    await h.pump(tester);
    expect(await h.store.discard(old), isTrue);
    final replacement = await h.seed('work-one');
    expect(replacement.rowId, isNot(old.rowId));
    await tester.tap(find.text('work-one'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Local recovery could not be read'),
      findsOneWidget,
    );
    expect(find.text('Resume local changes'), findsNothing);
    expect((await h.store.load(_key('work-one')))!.rowId, replacement.rowId);
  });

  testWidgets('multiple pages are explicitly loaded and scoped', (
    tester,
  ) async {
    for (var i = 0; i < 28; i++) {
      await h.seed('article-$i');
    }
    await h.pump(tester);
    expect(find.text('article-0'), findsOneWidget);
    final more = find.text('Load more');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(h.catalog.calls, 2);
    await tester.ensureVisible(find.text('article-27'));
    await tester.pumpAndSettle();
    expect(find.text('article-27'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets('localized catalog survives larger text $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(tester, locale: locale, scale: 1.5);
      expect(
        find.text(locale.languageCode == 'en' ? 'Local recoveries' : '本地恢复记录'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          locale.languageCode == 'en' ? 'nothing is published' : '不会发布',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
