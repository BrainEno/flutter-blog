import 'package:belog/l10n/app_localizations.dart';
import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUploadBloc extends Mock implements BlogUploadBloc {}

/// Mock that records dispatched events instead of relying on void stubs.
class RecordingUploadBloc extends Mock implements BlogUploadBloc {
  final List<BlogUploadEvent> events = [];

  @override
  void add(BlogUploadEvent event) => events.add(event);
}

class FakeDraftStore implements BlogDraftStore {
  final Map<String?, BlogDraft> drafts = {};
  final Map<(String, String?), BlogDraft> scopedDrafts = {};
  bool hasLegacy = false;
  String? lastLoadedUserId;
  String? lastLoadedId;
  bool loaded = false;
  Completer<BlogDraft?>? pendingLoad;
  Completer<void>? pendingSave;
  BlogDraft? saved;
  BlogDraft? discarded;
  bool failSave = false;

  @override
  Future<BlogDraft?> load(String? blogId, {required String userId}) async {
    loaded = true;
    lastLoadedId = blogId;
    lastLoadedUserId = userId;
    if (pendingLoad != null) return pendingLoad!.future;
    final draft = scopedDrafts[(userId, blogId)] ?? drafts[blogId];
    return draft?.userId == userId ? draft : null;
  }

  @override
  Future<bool> hasUnclaimedDrafts() async => hasLegacy;

  @override
  Future<void> save(BlogDraft draft) async {
    saved = draft;
    savedDrafts.add(draft);
    if (failSave) throw StateError('save failed');
    if (pendingSave != null) await pendingSave!.future;
  }

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async {
    discarded = draft;
    return true;
  }

  int deleteCalls = 0;
  String? deletedScope;
  DateTime? deletedOlderThan;
  String? deletedUserId;
  List<BlogDraft> savedDrafts = [];

  @override
  Future<int> deleteDraftsFor(
    String? blogId, {
    required String userId,
    DateTime? olderThan,
  }) async {
    deleteCalls++;
    deletedScope = blogId;
    deletedUserId = userId;
    deletedOlderThan = olderThan;
    return 1;
  }
}

BlogDraft makeDraft(String? id, String title, {String userId = 'user'}) =>
    BlogDraft(
      userId: userId,
      blogId: id,
      title: title,
      content: '草稿正文',
      tags: ['小说'],
      updatedAt: DateTime.utc(2024),
    );

class FakeSessionIdentity implements NowaveSessionIdentity {
  FakeSessionIdentity(this.userId);

  String? userId;
  int generation = 1;
  final changes = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;
  @override
  String? get accessToken => userId == null ? null : 'synthetic-token';
  @override
  int get sessionGeneration => generation;
  @override
  Stream<void> get identityChanges => changes.stream;

  void switchTo(String? nextUserId) {
    generation++;
    userId = nextUserId;
    changes.add(null);
  }
}

User testUser(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: 'Synthetic user',
  updatedAt: DateTime.utc(2024),
);

Blog makeBlog(String id) => Blog(
  id: id,
  title: '已发布标题',
  content: '已发布正文',
  posterId: 'author',
  imageUrl: '',
  tags: ['诗歌'],
  updatedAt: DateTime.utc(2025),
);

Future<void> openEditor(
  WidgetTester tester,
  FakeDraftStore store, {
  Blog? blog,
  Locale locale = const Locale('zh'),
  double textScale = 1,
  AppUserCubit? appUser,
  FakeSessionIdentity? session,
}) async {
  final user = appUser ?? (AppUserCubit()..updateUser(testUser('user')));
  final identity = session ?? FakeSessionIdentity('user');
  if (appUser == null) addTearDown(user.close);
  if (session == null) addTearDown(identity.changes.close);
  final bloc = MockUploadBloc();
  when(() => bloc.state).thenReturn(BlogUploadInitial());
  when(
    () => bloc.stream,
  ).thenAnswer((_) => const Stream<BlogUploadState>.empty());
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<BlogUploadBloc>.value(value: bloc),
          BlocProvider<AppUserCubit>.value(value: user),
        ],
        child: BlogEditorPage(
          blog: blog,
          draftStore: store,
          sessionIdentity: identity,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the editor with a bloc whose state stream we control.
Future<RecordingUploadBloc> openEditorLive(
  WidgetTester tester,
  FakeDraftStore store, {
  Blog? blog,
  required StreamController<BlogUploadState> states,
  AppUserCubit? appUser,
  FakeSessionIdentity? session,
}) async {
  final bloc = RecordingUploadBloc();
  when(() => bloc.state).thenReturn(BlogUploadInitial());
  when(() => bloc.stream).thenAnswer((_) => states.stream);
  final user = appUser ?? (AppUserCubit()..updateUser(testUser('user')));
  final identity = session ?? FakeSessionIdentity('user');
  if (appUser == null) addTearDown(user.close);
  if (session == null) addTearDown(identity.changes.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      home: MultiBlocProvider(
        providers: [
          BlocProvider<BlogUploadBloc>.value(value: bloc),
          BlocProvider<AppUserCubit>.value(value: user),
        ],
        child: BlogEditorPage(
          blog: blog,
          draftStore: store,
          sessionIdentity: identity,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

String titleText(WidgetTester tester) => tester
    .widget<TextFormField>(find.byType(TextFormField).first)
    .controller!
    .text;

Future<void> tapSaveDraft(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存草稿'));
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('editor supports larger text and localized controls: $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        previousErrorHandler?.call(details);
      };
      try {
        final l10n = lookupAppLocalizations(locale);
        await openEditor(
          tester,
          FakeDraftStore(),
          locale: locale,
          textScale: 2,
        );
        expect(find.text(l10n.editorNewTitle), findsOneWidget);
        expect(find.byTooltip(l10n.uploadCoverHint), findsOneWidget);
        final preview = find.text(l10n.editorSegmentPreview);
        await tester.ensureVisible(preview);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(find.text(l10n.previewEmptyBody), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = previousErrorHandler;
      }
    });
  }

  testWidgets('an existing article asks for its own draft, not a new draft', (
    tester,
  ) async {
    final store = FakeDraftStore()
      ..drafts[null] = makeDraft(null, '新文章草稿')
      ..drafts['article-b'] = makeDraft('article-b', '另一篇草稿');
    await openEditor(tester, store, blog: makeBlog('article-a'));
    expect(store.lastLoadedId, 'article-a');
    expect(find.text('发现草稿'), findsNothing);
    expect(titleText(tester), '已发布标题');
  });

  testWidgets('new article asks for the null-ID draft', (tester) async {
    final store = FakeDraftStore()..drafts[null] = makeDraft(null, '新文章草稿');
    await openEditor(tester, store);
    expect(store.loaded, isTrue);
    expect(store.lastLoadedId, isNull);
    expect(find.text('发现草稿'), findsOneWidget);
    expect(titleText(tester), isEmpty);
    await tester.tap(find.text('恢复草稿'));
    await tester.pumpAndSettle();
    expect(titleText(tester), '新文章草稿');
  });

  testWidgets('published content stays until the user restores the draft', (
    tester,
  ) async {
    final store = FakeDraftStore()
      ..drafts['article-a'] = makeDraft('article-a', '旧草稿标题');
    await openEditor(tester, store, blog: makeBlog('article-a'));
    expect(titleText(tester), '已发布标题');
    expect(find.textContaining('比已发布文章旧'), findsOneWidget);
    await tester.tap(find.text('恢复草稿'));
    await tester.pumpAndSettle();
    expect(titleText(tester), '旧草稿标题');
  });

  testWidgets(
    'discard leaves article content intact and discards only the draft',
    (tester) async {
      final draft = makeDraft('article-a', '旧草稿标题');
      final store = FakeDraftStore()..drafts['article-a'] = draft;
      await openEditor(tester, store, blog: makeBlog('article-a'));
      await tester.tap(find.text('丢弃草稿'));
      await tester.pumpAndSettle();
      expect(store.discarded, same(draft));
      expect(titleText(tester), '已发布标题');
    },
  );

  testWidgets('late load cannot replace a manually saved draft', (
    tester,
  ) async {
    final store = FakeDraftStore()..pendingLoad = Completer<BlogDraft?>();
    await openEditor(tester, store, blog: makeBlog('article-a'));
    await tapSaveDraft(tester);
    store.pendingLoad!.complete(makeDraft('article-a', '过期草稿'));
    await tester.pumpAndSettle();
    expect(find.text('发现草稿'), findsNothing);
    expect(titleText(tester), '已发布标题');
  });

  testWidgets('manual save takes a snapshot and reports failures', (
    tester,
  ) async {
    final store = FakeDraftStore()..pendingSave = Completer<void>();
    await openEditor(tester, store, blog: makeBlog('article-a'));
    await tapSaveDraft(tester);
    expect(store.saved!.title, '已发布标题');
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, '修改后的标题');
    expect(store.saved!.title, '已发布标题');
    store.pendingSave!.completeError(StateError('save failed'));
    await tester.pumpAndSettle();
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
  });

  testWidgets('auto-save writes a draft after 2s of inactivity', (
    tester,
  ) async {
    final store = FakeDraftStore();
    final states = StreamController<BlogUploadState>.broadcast();
    final bloc = await openEditorLive(tester, store, states: states);

    await tester.enterText(find.byType(TextFormField).first, '自动保存标题');
    await tester.pump();
    expect(store.saved, isNull, reason: 'nothing saved before the delay');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(store.savedDrafts, isNotEmpty);
    expect(store.savedDrafts.last.title, '自动保存标题');
    expect(find.text('草稿已自动保存'), findsOneWidget);
    // Auto-save must never publish anything.
    expect(bloc.events, isEmpty);
    await states.close();
  });

  testWidgets('blank editor does not auto-save', (tester) async {
    final store = FakeDraftStore();
    final states = StreamController<BlogUploadState>.broadcast();
    await openEditorLive(tester, store, states: states);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(store.savedDrafts, isEmpty);
    await states.close();
  });

  testWidgets('publish success clears only its exact saved snapshot', (
    tester,
  ) async {
    final store = FakeDraftStore();
    final states = StreamController<BlogUploadState>.broadcast();
    final bloc = await openEditorLive(
      tester,
      store,
      blog: makeBlog('article-a'),
      states: states,
    );

    // Edit something so a draft exists before publishing.
    await tester.enterText(find.byType(TextFormField).first, '发布前修改');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(store.savedDrafts, isNotEmpty);
    final savesBeforePublish = store.savedDrafts.length;

    await tester.tap(find.text('发布'));
    await tester.pump();
    expect(bloc.events.single, isA<UpdateBlogEvent>());

    states.add(BlogUploadSuccess());
    await tester.pumpAndSettle();

    expect(store.deleteCalls, 0);
    expect(store.discarded?.blogId, 'article-a');
    expect(store.discarded?.userId, 'user');
    expect(store.discarded?.title, '发布前修改');
    expect(
      store.savedDrafts.length,
      savesBeforePublish + 1,
      reason: 'save the exact request once, but do not resurrect it on dispose',
    );
    await states.close();
  });

  testWidgets('another account cannot recover the first account new draft', (
    tester,
  ) async {
    final store = FakeDraftStore()
      ..drafts[null] = makeDraft(null, 'private A', userId: 'account-A');
    final user = AppUserCubit()..updateUser(testUser('account-B'));
    final identity = FakeSessionIdentity('account-B');
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    await openEditor(tester, store, appUser: user, session: identity);

    expect(store.lastLoadedUserId, 'account-B');
    expect(find.text('发现草稿'), findsNothing);
    expect(find.text('private A'), findsNothing);
    expect(titleText(tester), isEmpty);
  });

  testWidgets('an in-flight load is hidden after an account switch', (
    tester,
  ) async {
    final store = FakeDraftStore()..pendingLoad = Completer<BlogDraft?>();
    final user = AppUserCubit()..updateUser(testUser('account-A'));
    final identity = FakeSessionIdentity('account-A');
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    await openEditor(tester, store, appUser: user, session: identity);

    identity.switchTo('account-B');
    user.updateUser(testUser('account-B'));
    store.pendingLoad!.complete(
      makeDraft(null, 'private A', userId: 'account-A'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('private A'), findsNothing);
    expect(find.text('发现草稿'), findsNothing);
    expect(find.textContaining('登录状态已改变'), findsOneWidget);
    expect(store.savedDrafts, isEmpty);
  });

  testWidgets('account switch dismisses the old recovery dialog', (
    tester,
  ) async {
    final store = FakeDraftStore()
      ..scopedDrafts[('account-A', null)] = makeDraft(
        null,
        'private A',
        userId: 'account-A',
      );
    final user = AppUserCubit()..updateUser(testUser('account-A'));
    final identity = FakeSessionIdentity('account-A');
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    await openEditor(tester, store, appUser: user, session: identity);
    expect(find.text('发现草稿'), findsOneWidget);

    identity.switchTo('account-B');
    user.updateUser(testUser('account-B'));
    await tester.pumpAndSettle();
    expect(find.text('发现草稿'), findsNothing);
    expect(find.text('private A'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(store.discarded, isNull);
  });

  testWidgets('pending edits are saved only for the original account', (
    tester,
  ) async {
    final store = FakeDraftStore();
    final user = AppUserCubit()..updateUser(testUser('account-A'));
    final identity = FakeSessionIdentity('account-A');
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    await openEditor(tester, store, appUser: user, session: identity);

    await tester.enterText(find.byType(TextFormField).first, 'A unsaved text');
    await tester.pump();
    identity.switchTo('account-B');
    user.updateUser(testUser('account-B'));
    await tester.pumpAndSettle();
    expect(store.savedDrafts, isNotEmpty);
    expect(
      store.savedDrafts.every((draft) => draft.userId == 'account-A'),
      isTrue,
    );
    expect(store.savedDrafts.last.title, 'A unsaved text');
    expect(find.text('A unsaved text'), findsNothing);
  });

  testWidgets(
    'an old pending manual save never reports success to a new account',
    (tester) async {
      final store = FakeDraftStore()..pendingSave = Completer<void>();
      final user = AppUserCubit()..updateUser(testUser('account-A'));
      final identity = FakeSessionIdentity('account-A');
      addTearDown(user.close);
      addTearDown(identity.changes.close);
      await openEditor(tester, store, appUser: user, session: identity);
      await tester.enterText(find.byType(TextFormField).first, 'A writing');
      await tapSaveDraft(tester);
      identity.switchTo('account-B');
      user.updateUser(testUser('account-B'));
      store.pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(find.text('草稿已保存'), findsNothing);
      expect(
        store.savedDrafts.every((draft) => draft.userId == 'account-A'),
        isTrue,
      );
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets('an unresolved session cannot read local drafts', (tester) async {
    final store = FakeDraftStore();
    final user = AppUserCubit()..updateUser(testUser('account-A'));
    final identity = FakeSessionIdentity(null);
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    await openEditor(tester, store, appUser: user, session: identity);
    expect(store.loaded, isFalse);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('登录状态已改变'), findsOneWidget);
  });

  testWidgets('switching during publish preparation prevents any event', (
    tester,
  ) async {
    final store = FakeDraftStore()..pendingSave = Completer<void>();
    final states = StreamController<BlogUploadState>.broadcast();
    final user = AppUserCubit()..updateUser(testUser('account-A'));
    final identity = FakeSessionIdentity('account-A');
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    addTearDown(states.close);
    final bloc = await openEditorLive(
      tester,
      store,
      blog: makeBlog('article-a'),
      states: states,
      appUser: user,
      session: identity,
    );
    await tester.enterText(find.byType(TextFormField).first, 'private A');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pump();
    identity.switchTo('account-B');
    user.updateUser(testUser('account-B'));
    store.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(bloc.events, isEmpty);
    expect(
      store.savedDrafts.every((draft) => draft.userId == 'account-A'),
      isTrue,
    );
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets(
    'disposing during an unconfirmed publish keeps its local snapshot',
    (tester) async {
      final store = FakeDraftStore();
      final states = StreamController<BlogUploadState>.broadcast();
      addTearDown(states.close);
      final bloc = await openEditorLive(
        tester,
        store,
        blog: makeBlog('article-a'),
        states: states,
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'private pending',
      );
      await tester.pump();
      await tester.tap(find.text('发布'));
      await tester.pump();
      expect(bloc.events.single, isA<UpdateBlogEvent>());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(store.savedDrafts.last.userId, 'user');
      expect(store.savedDrafts.last.title, 'private pending');
      expect(store.discarded, isNull);
    },
  );

  testWidgets('local snapshot failure does not dispatch a publish', (
    tester,
  ) async {
    final store = FakeDraftStore()..failSave = true;
    final states = StreamController<BlogUploadState>.broadcast();
    addTearDown(states.close);
    final bloc = await openEditorLive(
      tester,
      store,
      blog: makeBlog('article-a'),
      states: states,
    );
    await tester.tap(find.text('发布'));
    await tester.pump();
    expect(bloc.events, isEmpty);
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
  });

  testWidgets('same-account relogin invalidates an in-flight publish', (
    tester,
  ) async {
    final store = FakeDraftStore();
    final states = StreamController<BlogUploadState>.broadcast();
    final user = AppUserCubit()..updateUser(testUser('account-A'));
    final identity = FakeSessionIdentity('account-A');
    addTearDown(user.close);
    addTearDown(identity.changes.close);
    addTearDown(states.close);
    final bloc = await openEditorLive(
      tester,
      store,
      blog: makeBlog('article-a'),
      states: states,
      appUser: user,
      session: identity,
    );
    await tester.enterText(find.byType(TextFormField).first, 'pending publish');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pump();
    final event = bloc.events.single as UpdateBlogEvent;
    expect(event.sessionFence.userId, 'account-A');
    expect(event.sessionFence.generation, 1);

    identity.switchTo('account-A');
    await tester.pump();
    states.add(BlogUploadSuccess());
    await tester.pumpAndSettle();
    expect(store.deleteCalls, 0);
    expect(store.savedDrafts.last.userId, 'account-A');
    expect(store.savedDrafts.last.title, 'pending publish');
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('typing while a draft is loading keeps the new text', (
    tester,
  ) async {
    final store = FakeDraftStore()..pendingLoad = Completer<BlogDraft?>();
    await openEditor(tester, store);
    await tester.enterText(find.byType(TextFormField).first, 'newer text');
    store.pendingLoad!.complete(makeDraft(null, 'older text'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('发现草稿'), findsNothing);
    expect(titleText(tester), 'newer text');
    expect(store.savedDrafts.last.title, 'newer text');
    expect(store.savedDrafts.last.userId, 'user');
  });

  testWidgets('unattributed legacy drafts are disclosed without content', (
    tester,
  ) async {
    final store = FakeDraftStore()..hasLegacy = true;
    await openEditor(tester, store);
    expect(find.textContaining('旧版草稿仍保存在设备中'), findsOneWidget);
    expect(find.textContaining('无法确认所属账号'), findsOneWidget);
  });

  testWidgets('the editor menu no longer offers article deletion '
      '(backend gap G1: no DELETE endpoint)', (tester) async {
    // Seed a draft so the recovery dialog appears; discard it to reach the
    // interactive editor (the delete entry used to live in its menu).
    final store = FakeDraftStore()
      ..drafts['article-a'] = makeDraft('article-a', '旧草稿标题');
    final states = StreamController<BlogUploadState>.broadcast();
    final bloc = await openEditorLive(
      tester,
      store,
      blog: makeBlog('article-a'),
      states: states,
    );
    await tester.tap(find.text('丢弃草稿'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('删除文章'), findsNothing);
    expect(find.text('保存更改'), findsOneWidget);
    expect(bloc.events, isEmpty);
    await states.close();
  });
}
