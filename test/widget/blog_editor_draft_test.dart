import 'dart:async';

import 'package:belog/features/blog/data/datasources/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/presentation/blocs/bog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUploadBloc extends Mock implements BlogUploadBloc {}

class FakeDraftStore implements BlogDraftStore {
  final Map<String?, BlogDraft> drafts = {};
  String? lastLoadedId;
  bool loaded = false;
  Completer<BlogDraft?>? pendingLoad;
  Completer<void>? pendingSave;
  BlogDraft? saved;
  BlogDraft? discarded;
  bool failSave = false;

  @override
  Future<BlogDraft?> load(String? blogId) async {
    loaded = true;
    lastLoadedId = blogId;
    if (pendingLoad != null) return pendingLoad!.future;
    return drafts[blogId];
  }

  @override
  Future<void> save(BlogDraft draft) async {
    saved = draft;
    if (failSave) throw StateError('save failed');
    if (pendingSave != null) await pendingSave!.future;
  }

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async {
    discarded = draft;
    return true;
  }
}

BlogDraft makeDraft(String? id, String title) => BlogDraft(
      blogId: id,
      title: title,
      content: '草稿正文',
      tags: ['小说'],
      updatedAt: DateTime.utc(2024),
    );

Blog makeBlog(String id) => Blog(
      iid: 1,
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
}) async {
  final bloc = MockUploadBloc();
  when(() => bloc.state).thenReturn(BlogUploadInitial());
  when(() => bloc.stream)
      .thenAnswer((_) => const Stream<BlogUploadState>.empty());
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<BlogUploadBloc>.value(
        value: bloc,
        child: BlogEditorPage(blog: blog, draftStore: store),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  testWidgets('an existing article asks for its own draft, not a new draft',
      (tester) async {
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

  testWidgets('published content stays until the user restores the draft',
      (tester) async {
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
  });

  testWidgets('late load cannot replace a manually saved draft',
      (tester) async {
    final store = FakeDraftStore()..pendingLoad = Completer<BlogDraft?>();
    await openEditor(tester, store, blog: makeBlog('article-a'));
    await tapSaveDraft(tester);
    store.pendingLoad!.complete(makeDraft('article-a', '过期草稿'));
    await tester.pumpAndSettle();
    expect(find.text('发现草稿'), findsNothing);
    expect(titleText(tester), '已发布标题');
  });

  testWidgets('manual save takes a snapshot and reports failures',
      (tester) async {
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
}
