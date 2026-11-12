import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_editor_page.dart';
import 'package:belog/features/blog/presentation/pages/user_blogs_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/structured_article_fixtures.dart';

class _Identity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 9;
  @override
  Stream<void> get identityChanges => const Stream.empty();
}

class _Reader implements StructuredEditionReader {
  StructuredBodyKey? seenKey;
  NowaveSessionFence? seenFence;
  int calls = 0;
  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async {
    calls++;
    seenKey = key;
    seenFence = fence;
    return const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.unsupportedDocument,
    );
  }
}

class _Blogs extends Mock implements BlogByBloc {
  _Blogs(this.blog);
  final Blog blog;
  final events = <BlogByEvent>[];
  @override
  BlogByState get state => GetBlogsByUserSuccess(blogs: [blog]);
  @override
  Stream<BlogByState> get stream => const Stream.empty();
  @override
  void add(BlogByEvent event) => events.add(event);
}

class _Uploads extends Mock implements BlogUploadBloc {
  final events = <BlogUploadEvent>[];
  @override
  BlogUploadState get state => BlogUploadInitial();
  @override
  Stream<BlogUploadState> get stream => const Stream.empty();
  @override
  void add(BlogUploadEvent event) => events.add(event);
}

BlogModel _blog({
  String id = 'server-uuid',
  String author = 'author',
  String locale = 'en',
}) => BlogModel.fromNowaveArticle({
  ...structuredArticle(),
  'id': id,
  'authorId': author,
  'locale': locale,
}).copyWith(imageUrl: '');

class _EntryHarness {
  _EntryHarness(Blog blog) {
    db = AppDatabase(NativeDatabase.memory());
    identity = _Identity();
    reader = _Reader();
    blogs = _Blogs(blog);
    uploads = _Uploads();
    user = AppUserCubit()
      ..updateUser(
        User(
          id: 'author',
          email: 'user@example.invalid',
          name: 'Author',
          updatedAt: DateTime.utc(2026),
        ),
      );
    opener = OpenStructuredEditingSession(
      reader: reader,
      store: SqliteStructuredBodyRecoveryStore(
        db,
        apiBaseUrl: Uri.parse('https://api.example.invalid'),
      ),
      identity: identity,
    );
  }
  late final AppDatabase db;
  late final _Identity identity;
  late final _Reader reader;
  late final _Blogs blogs;
  late final _Uploads uploads;
  late final AppUserCubit user;
  late final OpenStructuredEditingSession opener;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppUserCubit>.value(value: user),
            BlocProvider<BlogByBloc>.value(value: blogs),
            BlocProvider<BlogUploadBloc>.value(value: uploads),
          ],
          child: UserBlogsPage(structuredOpener: opener),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await user.close();
    await db.close();
  }
}

void main() {
  testWidgets('author archive opens exact ID and locale, never the slug', (
    tester,
  ) async {
    final h = _EntryHarness(_blog(locale: 'zh-TW'));
    addTearDown(h.close);
    await h.pump(tester);
    await tester.tap(find.text('Sample title'));
    await tester.pumpAndSettle();
    expect(find.byType(StructuredLocalEditorPage), findsOneWidget);
    expect(h.reader.calls, 1);
    expect(h.reader.seenKey!.articleId, 'server-uuid');
    expect(h.reader.seenKey!.locale, 'zh-TW');
    expect(h.reader.seenKey!.userId, 'author');
    expect(h.reader.seenFence!.userId, 'author');
    expect(h.reader.seenFence!.generation, 9);
    expect(h.uploads.events, isEmpty);
    expect(
      find.textContaining('unsupported or damaged blocks'),
      findsOneWidget,
    );
  });

  testWidgets('missing stable ID refuses to open rather than using slug', (
    tester,
  ) async {
    final h = _EntryHarness(_blog(id: ''));
    addTearDown(h.close);
    await h.pump(tester);
    await tester.tap(find.text('Sample title'));
    await tester.pumpAndSettle();
    expect(h.reader.calls, 0);
    expect(find.byType(StructuredLocalEditorPage), findsNothing);
    expect(
      find.textContaining('Cannot open this edition safely'),
      findsOneWidget,
    );
    expect(h.uploads.events, isEmpty);
  });

  testWidgets('unknown language does not fall back to current content locale', (
    tester,
  ) async {
    final h = _EntryHarness(_blog(locale: ''));
    addTearDown(h.close);
    await h.pump(tester);
    await tester.tap(find.text('Sample title'));
    await tester.pumpAndSettle();
    expect(h.reader.calls, 0);
    expect(find.byType(StructuredLocalEditorPage), findsNothing);
    expect(
      find.textContaining('Cannot open this edition safely'),
      findsOneWidget,
    );
  });

  testWidgets('stale author list cannot open under the replacement account', (
    tester,
  ) async {
    final h = _EntryHarness(_blog());
    addTearDown(h.close);
    h.identity.activeUserId = 'other';
    h.identity.sessionGeneration++;
    await h.pump(tester);
    await tester.tap(find.text('Sample title'));
    await tester.pumpAndSettle();
    expect(h.reader.calls, 0);
    expect(find.byType(StructuredLocalEditorPage), findsNothing);
    expect(
      find.textContaining('Cannot open this edition safely'),
      findsOneWidget,
    );
  });

  testWidgets('a mismatched article owner is refused before a request', (
    tester,
  ) async {
    final h = _EntryHarness(_blog(author: 'other'));
    addTearDown(h.close);
    await h.pump(tester);
    await tester.tap(find.text('Sample title'));
    await tester.pumpAndSettle();
    expect(h.reader.calls, 0);
    expect(find.byType(StructuredLocalEditorPage), findsNothing);
    expect(h.uploads.events, isEmpty);
  });
}
