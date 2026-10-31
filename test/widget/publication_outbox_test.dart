import 'dart:convert';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_publication_outbox.dart';
import 'package:belog/features/blog/data/datasources/blog_draft_store.dart';
import 'package:belog/features/blog/data/publication_outbox.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/features/blog/presentation/pages/publication_outbox_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockUploadBloc extends Mock implements BlogUploadBloc {}

class _Drafts implements BlogDraftStore {
  final saved = <BlogDraft>[];
  @override
  Future<BlogDraft?> load(String? blogId) async => null;
  @override
  Future<void> save(BlogDraft draft) async {
    saved.add(draft);
  }

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async => true;
  @override
  Future<int> deleteDraftsFor(String? blogId, {DateTime? olderThan}) async => 0;
}

class _SessionStore implements NowaveSessionStore {
  NowaveSessionData? session;
  @override
  Future<NowaveSessionData?> read() async => session;
  @override
  Future<void> write(NowaveSessionData value) async {
    session = value;
  }

  @override
  Future<void> clear() async {
    session = null;
  }
}

class _Offline implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => false;
}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
  updatedAt: DateTime.utc(2026),
);
NowaveSessionData _session(String id) => NowaveSessionData(
  userId: id,
  email: '$id@example.invalid',
  accessToken: '$id-token',
  refreshToken: '$id-refresh',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);
NowaveTokenPair _pair(String id) => NowaveTokenPair(
  accessToken: '$id-token',
  refreshToken: '$id-refresh',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

class _Fixture {
  _Fixture(this.db, this.store, this.outbox, this.sessions, this.user);
  final AppDatabase db;
  final SqlitePublicationOutbox store;
  final PublicationOutbox outbox;
  final NowaveSessionManager sessions;
  final AppUserCubit user;
  Future<void> close() async {
    outbox.dispose();
    await user.close();
    await db.close();
  }
}

Future<_Fixture> _fixture() async {
  final db = AppDatabase(NativeDatabase.memory());
  final store = SqlitePublicationOutbox(db);
  final client = NowaveApiClient(
    baseUrl: Uri.parse('https://api.example.invalid'),
    httpClient: MockClient(
      (_) async => http.Response(jsonEncode({'data': null}), 200),
    ),
  );
  final sessionStore = _SessionStore()..session = _session('alice');
  final sessions = NowaveSessionManager(client: client, store: sessionStore);
  await sessions.restore();
  final user = AppUserCubit()..updateUser(_user('alice'));
  final outbox = PublicationOutbox(
    store: store,
    client: client,
    sessions: sessions,
    appUser: user,
    connection: _Offline(),
  );
  return _Fixture(db, store, outbox, sessions, user);
}

void main() {
  testWidgets(
    'auto-saved draft is not a publication; queue requires confirmation',
    (tester) async {
      final f = await _fixture();
      final drafts = _Drafts();
      final bloc = _MockUploadBloc();
      when(() => bloc.state).thenReturn(BlogUploadInitial());
      when(
        () => bloc.stream,
      ).thenAnswer((_) => const Stream<BlogUploadState>.empty());
      GetIt.instance.registerSingleton<PublicationOutbox>(f.outbox);
      addTearDown(() async {
        await GetIt.instance.unregister<PublicationOutbox>();
        await f.close();
      });
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AppUserCubit>.value(value: f.user),
            BlocProvider<BlogUploadBloc>.value(value: bloc),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => BlogEditorPage(draftStore: drafts),
                    ),
                  ),
                  child: const Text('open editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, '离线文章');
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(find.byType(TextFormField).last, '正文');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(drafts.saved, isNotEmpty);
      expect(await f.store.list('alice'), isEmpty);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('联网后发布'));
      await tester.pumpAndSettle();
      expect(await f.store.list('alice'), isEmpty);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(await f.store.list('alice'), isEmpty);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('联网后发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入队列'));
      await tester.pumpAndSettle();
      final items = await f.store.list('alice');
      expect(items, hasLength(1));
      expect(items.single.title, '离线文章');
      expect(items.single.content, '正文');
      expect(items.single.publishedSlug, isNull);
    },
  );

  testWidgets('queue hides other accounts and locks an uncertain article', (
    tester,
  ) async {
    final f = await _fixture();
    addTearDown(f.close);
    final alice = await f.store.enqueue(
      ownerId: 'alice',
      title: 'Alice only',
      content: 'A',
      tags: const [],
    );
    await f.store.enqueue(
      ownerId: 'bob',
      title: 'Bob only',
      content: 'B',
      tags: const [],
    );
    await f.store.claimNext('alice');
    await f.store.beginArticle('alice', alice.id, '{}');
    await f.store.failAttempt(
      'alice',
      alice.id,
      code: 'article.outcomeUnknown',
    );
    await tester.pumpWidget(
      BlocProvider<AppUserCubit>.value(
        value: f.user,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PublicationOutboxPage(outbox: f.outbox),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alice only'), findsOneWidget);
    expect(find.text('Bob only'), findsNothing);
    expect(find.text('检查发布结果'), findsOneWidget);
    expect(find.text('编辑快照'), findsNothing);
    expect(find.text('取消请求'), findsNothing);
    expect(find.text('重试'), findsNothing);

    await f.sessions.adoptSession(_pair('bob'), email: 'bob@example.invalid');
    await f.sessions.updateUserId('bob');
    f.user.updateUser(_user('bob'));
    // The broadcast cubit event is delivered after the first frame; the
    // second frame renders the newly scoped FutureBuilder.
    await tester.pump();
    await tester.pump();
    expect(find.text('Alice only'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Bob only'), findsOneWidget);
    expect(find.text('Alice only'), findsNothing);
  });
}
