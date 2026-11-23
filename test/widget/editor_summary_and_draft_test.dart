import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

final _revision = ArticleRevision.parse('7')!;

/// Records the events the editor dispatches instead of publishing anything.
class _RecordingUploadBloc extends Mock implements BlogUploadBloc {
  final List<BlogUploadEvent> events = [];

  @override
  void add(BlogUploadEvent event) => events.add(event);
}

class _FakeDraftStore implements BlogDraftStore {
  BlogDraft? saved;

  @override
  Future<BlogDraft?> load(String? blogId, {required String userId}) async =>
      null;

  @override
  Future<void> save(BlogDraft draft) async => saved = draft;

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async => true;

  @override
  Future<bool> hasUnclaimedDrafts() async => false;

  @override
  Future<int> deleteDraftsFor(
    String? blogId, {
    required String userId,
    DateTime? olderThan,
  }) async => 0;
}

class _FakeCategoryRepository implements CategoryRepository {
  _FakeCategoryRepository(this.categories);

  final List<CategoryRef> categories;

  @override
  Future<Either<Failure, List<CategoryRef>>> listCategories() async =>
      right(categories);

  @override
  Future<Either<Failure, CategoryRef?>> getCategory(String slug) async =>
      right(null);

  @override
  Future<Either<Failure, List<Blog>>> getArticlesByCategory(
    String slug, {
    required int offset,
  }) async => right(const []);
}

class _FakeSession implements NowaveSessionIdentity {
  _FakeSession(this.userId);

  String? userId;
  int generation = 1;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;
  @override
  String? get accessToken => userId == null ? null : 'synthetic-token';
  @override
  int get sessionGeneration => generation;
  @override
  Stream<void> get identityChanges => _changes.stream;

  void dispose() => _changes.close();
}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: 'Synthetic user',
  updatedAt: DateTime.utc(2024),
);

Blog _article({bool isDraft = false, String summary = '旧摘要'}) => BlogModel(
  id: 'a-slug',
  articleId: 'article-a-slug',
  articleRevision: _revision,
  title: '已发布标题',
  content: '已发布正文',
  summary: summary,
  serverSummary: summary,
  posterId: 'author',
  imageUrl: '',
  tags: const ['诗歌'],
  isDraft: isDraft,
  updatedAt: DateTime.utc(2025),
);

Future<_RecordingUploadBloc> _openEditor(
  WidgetTester tester, {
  Blog? blog,
}) async {
  final bloc = _RecordingUploadBloc();
  when(() => bloc.state).thenReturn(BlogUploadInitial());
  when(
    () => bloc.stream,
  ).thenAnswer((_) => const Stream<BlogUploadState>.empty());
  final user = AppUserCubit()..updateUser(_user('user'));
  final session = _FakeSession('user');
  addTearDown(user.close);
  addTearDown(session.dispose);
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
          draftStore: _FakeDraftStore(),
          sessionIdentity: session,
          getCategories: GetCategories(
            _FakeCategoryRepository(const <CategoryRef>[]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

final _summaryField = find.byKey(const Key('editor-summary-field'));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the article summary is shown and an untouched one is kept', (
    tester,
  ) async {
    final bloc = await _openEditor(tester, blog: _article());

    await tester.ensureVisible(_summaryField);
    expect(tester.widget<TextField>(_summaryField).controller?.text, '旧摘要');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    final event = bloc.events.single as UpdateBlogEvent;
    // Null: the server keeps the summary it has.
    expect(event.summary, isNull);
    expect(event.publish, isTrue);
  });

  testWidgets('a rewritten summary is sent, trimmed', (tester) async {
    final bloc = await _openEditor(tester, blog: _article());

    await tester.ensureVisible(_summaryField);
    await tester.enterText(_summaryField, '  新的一句话  ');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect((bloc.events.single as UpdateBlogEvent).summary, '新的一句话');
  });

  testWidgets('clearing the summary asks the server for a fresh one', (
    tester,
  ) async {
    final bloc = await _openEditor(tester, blog: _article());

    await tester.ensureVisible(_summaryField);
    await tester.enterText(_summaryField, '');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect((bloc.events.single as UpdateBlogEvent).summary, '');
  });

  testWidgets('a new article can be stored as a private draft', (tester) async {
    final bloc = await _openEditor(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('editor-title-field')),
        matching: find.byType(EditableText),
      ),
      '草稿标题',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('editor-body-field')),
        matching: find.byType(EditableText),
      ),
      '草稿正文',
    );
    await tester.pump();

    await _openMenu(tester);
    // The local save keeps its own, now unambiguous, name.
    expect(find.text('保存到本机'), findsOneWidget);
    await tester.tap(find.text('存为草稿（仅自己可见）'));
    await tester.pumpAndSettle();

    final event = bloc.events.single as UploadBlogEvent;
    expect(event.publish, isFalse);
    expect(event.title, '草稿标题');
    // Never touched: no-wave writes the summary from the body.
    expect(event.summary, isNull);
  });

  testWidgets('a draft article says so and goes straight to the server', (
    tester,
  ) async {
    final bloc = await _openEditor(tester, blog: _article(isDraft: true));

    expect(find.byKey(const Key('editor-draft-notice')), findsOneWidget);
    await _openMenu(tester);
    // Publishing a draft is a first publication, not "saving changes".
    expect(find.text('保存并发布'), findsOneWidget);
    await tester.tap(find.byKey(const Key('editor-server-draft')));
    await tester.pumpAndSettle();

    // No confirmation: nothing readers can see changes.
    expect(find.byType(AlertDialog), findsNothing);
    final event = bloc.events.single as UpdateBlogEvent;
    expect(event.publish, isFalse);
  });

  testWidgets('taking a public article back to a draft asks first', (
    tester,
  ) async {
    final bloc = await _openEditor(tester, blog: _article());

    expect(find.byKey(const Key('editor-draft-notice')), findsNothing);
    await _openMenu(tester);
    expect(find.text('转为草稿（取消公开）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('editor-server-draft')));
    await tester.pumpAndSettle();
    expect(find.text('把这篇文章转为草稿？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(bloc.events, isEmpty);

    await _openMenu(tester);
    await tester.tap(find.byKey(const Key('editor-server-draft')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转为草稿'));
    await tester.pumpAndSettle();

    final event = bloc.events.single as UpdateBlogEvent;
    expect(event.publish, isFalse);
    expect(event.blogId, 'a-slug');
  });

  testWidgets('focus mode leaves the summary out', (tester) async {
    await _openEditor(tester, blog: _article());
    await tester.ensureVisible(_summaryField);
    expect(_summaryField, findsOneWidget);

    await tester.tap(find.byKey(const Key('editor-focus-mode')));
    await tester.pumpAndSettle();

    expect(_summaryField, findsNothing);
  });
}
