import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/design/components/no_wave_busy_mark.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/user_blogs_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/router/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _BlogByBloc extends Mock implements BlogByBloc {}

class _UploadBloc extends Mock implements BlogUploadBloc {}

class _Session implements NowaveSessionIdentity {
  @override
  String? get activeUserId => 'author';
  @override
  String? get accessToken => 'synthetic-token';
  @override
  int get sessionGeneration => 3;
  @override
  Stream<void> get identityChanges => const Stream<void>.empty();
}

/// An article as `/me/articles` lists it: with the revision a write needs.
Blog _listed(String id, {bool isDraft = false, ArticleDocument? document}) =>
    BlogModel(
      id: id,
      articleId: 'article-$id',
      articleRevision: ArticleRevision.parse('5'),
      title: 'Title $id',
      content: 'Body of $id',
      posterId: 'author',
      imageUrl: '',
      tags: const ['poetry'],
      isDraft: isDraft,
      locale: 'en',
      document: document,
      updatedAt: DateTime.utc(2026, 11, 1),
    );

Blog _blog(String id, {ArticleDocument? document}) => Blog(
  id: id,
  title: 'Title $id',
  content: 'Body of $id',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026, 11, 1),
  document: document,
);

ArticleTextBlock _paragraph(String text, {String? attribution}) =>
    ArticleTextBlock(
      id: text,
      kind: attribution == null
          ? ArticleTextKind.paragraph
          : ArticleTextKind.quote,
      text: text,
      runs: [ArticleInlineRun(text: text)],
      attribution: attribution,
    );

class _Harness {
  _Harness(List<Blog> blogs) {
    when(() => blogBy.state).thenReturn(GetBlogsByUserSuccess(blogs: blogs));
    when(() => blogBy.stream).thenAnswer((_) => byChanges.stream);
    when(() => blogBy.add(any())).thenAnswer((invocation) {
      events.add(invocation.positionalArguments.single as BlogByEvent);
    });
    when(() => upload.state).thenReturn(BlogUploadInitial());
    when(() => upload.stream).thenAnswer((_) => uploadChanges.stream);
    when(() => upload.add(any())).thenAnswer((invocation) {
      uploads.add(invocation.positionalArguments.single as BlogUploadEvent);
    });
    appUser.updateUser(
      User(
        id: 'author',
        email: 'author@example.invalid',
        name: 'Author',
        updatedAt: DateTime.utc(2026),
      ),
    );
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => UserBlogsPage(sessionIdentity: _Session()),
        ),
        GoRoute(
          path: RoutePaths.profileEditor,
          builder: (context, state) {
            opened.add(state.extra);
            return Scaffold(
              body: Column(
                children: [
                  const Text('editor'),
                  TextButton(
                    onPressed: () => context.pop(true),
                    child: const Text('saved'),
                  ),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('back'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  final blogBy = _BlogByBloc();
  final upload = _UploadBloc();
  final appUser = AppUserCubit();
  final byChanges = StreamController<BlogByState>.broadcast();
  final uploadChanges = StreamController<BlogUploadState>.broadcast();
  final opened = <Object?>[];
  late final GoRouter router;

  final events = <BlogByEvent>[];
  final uploads = <BlogUploadEvent>[];

  /// How many times the page has read the author's list so far.
  int get fetches => events.whereType<GetMyArticlesEvent>().length;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AppUserCubit>.value(value: appUser),
          BlocProvider<BlogByBloc>.value(value: blogBy),
          BlocProvider<BlogUploadBloc>.value(value: upload),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    router.dispose();
    await byChanges.close();
    await uploadChanges.close();
    await appUser.close();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(GetMyArticlesEvent(userId: 'x'));
    registerFallbackValue(const DeleteBlogEvent(blogId: 'x'));
  });

  testWidgets('the write button opens a blank editor and a publish refreshes', (
    tester,
  ) async {
    final harness = _Harness([_blog('one')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    expect(harness.fetches, 1);

    await tester.tap(find.byKey(const Key('my-articles-write')));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);
    // The route may build more than once; every build had no article.
    expect(harness.opened, isNotEmpty);
    expect(harness.opened.every((extra) => extra == null), isTrue);

    await tester.tap(find.text('saved'));
    await tester.pumpAndSettle();
    expect(find.byType(UserBlogsPage), findsOneWidget);
    expect(harness.fetches, 2, reason: 'one more read after the publish');
  });

  testWidgets('leaving the editor without publishing does not re-read', (
    tester,
  ) async {
    final harness = _Harness([_blog('one')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    expect(harness.fetches, 1);

    await tester.tap(find.byKey(const Key('my-articles-write')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(harness.fetches, 1);
  });

  testWidgets('plain and structured articles both open in the editor', (
    tester,
  ) async {
    final plain = _blog('plain');
    final structured = _blog(
      'structured',
      document: ArticleDocument(
        version: 1,
        blocks: [_paragraph('A structured body')],
      ),
    );
    final harness = _Harness([plain, structured]);
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.tap(find.text('Title plain'));
    await tester.pumpAndSettle();
    expect(harness.opened.last, same(plain));
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Title structured'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title structured'));
    await tester.pumpAndSettle();
    expect(harness.opened.last, same(structured));
  });

  testWidgets('a body the editor cannot keep is explained, not opened', (
    tester,
  ) async {
    final rich = _blog(
      'rich',
      document: ArticleDocument(
        version: 1,
        blocks: [_paragraph('Quoted words', attribution: 'Someone')],
      ),
    );
    expect(rich.editableBody, isNull);
    final harness = _Harness([rich]);
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.tap(find.text('Title rich'));
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.articleNotEditableInApp), findsOneWidget);
    expect(harness.opened, isEmpty);
  });

  testWidgets('every article row offers its actions', (tester) async {
    final harness = _Harness([_blog('one'), _blog('two')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byTooltip(l10n.myArticleActionsTooltip), findsNWidgets(2));
  });

  testWidgets('delete from the actions still asks first', (tester) async {
    final harness = _Harness([_listed('one')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.longPress(find.text('Title one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-article-action-delete')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.deleteArticleBody('Title one')), findsOneWidget);
    await tester.tap(find.text(l10n.actionDelete));
    await tester.pumpAndSettle();

    expect(harness.uploads.single, const DeleteBlogEvent(blogId: 'one'));
  });

  testWidgets('a draft is published from the list, unchanged', (tester) async {
    final harness = _Harness([_listed('draft', isDraft: true)]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(harness.fetches, 1);

    await tester.tap(find.byTooltip(l10n.myArticleActionsTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.myArticleActionPublish));
    // The row shows it is busy; its mark keeps moving, so no settling.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final event = harness.uploads.single as UpdateBlogEvent;
    expect(event.publish, isTrue);
    expect(event.blogId, 'draft');
    expect(event.title, 'Title draft');
    expect(event.content, 'Body of draft');
    expect(event.tags, ['poetry']);
    expect(event.locale, 'en');
    expect(event.expectedRevision, ArticleRevision.parse('5'));
    expect(event.sessionFence.userId, 'author');
    expect(event.sessionFence.generation, 3);
    // Nothing else changes: cover, categories and summary stay the server's.
    expect(event.image, isNull);
    expect(event.uploadedCoverUrl, isNull);
    expect(event.categoryIds, isNull);
    expect(event.summary, isNull);
    expect(find.byType(NoWaveBusyMark), findsOneWidget);
    expect(find.byTooltip(l10n.myArticleActionsTooltip), findsNothing);

    harness.uploadChanges.add(BlogUploadSuccess());
    await tester.pumpAndSettle();
    expect(find.text(l10n.myArticlePublished), findsOneWidget);
    expect(harness.fetches, 2, reason: 'the badge must follow the server');
    expect(find.byType(NoWaveBusyMark), findsNothing);
  });

  testWidgets('taking a public article back to a draft asks first', (
    tester,
  ) async {
    final harness = _Harness([_listed('live')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    Future<void> chooseUnpublish() async {
      await tester.tap(find.byTooltip(l10n.myArticleActionsTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.editorUnpublishToDraft));
      await tester.pumpAndSettle();
      expect(find.text(l10n.editorUnpublishTitle), findsOneWidget);
    }

    await chooseUnpublish();
    await tester.tap(find.text(l10n.actionCancel));
    await tester.pumpAndSettle();
    expect(harness.uploads, isEmpty);

    await chooseUnpublish();
    await tester.tap(find.text(l10n.editorUnpublishConfirm));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final event = harness.uploads.single as UpdateBlogEvent;
    expect(event.publish, isFalse);

    harness.uploadChanges.add(BlogUploadSuccess());
    await tester.pumpAndSettle();
    expect(find.text(l10n.myArticleUnpublished), findsOneWidget);
  });

  testWidgets('a conflict refreshes the list instead of overwriting', (
    tester,
  ) async {
    final harness = _Harness([_listed('draft', isDraft: true)]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.myArticleActionsTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.myArticleActionPublish));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    harness.uploadChanges.add(
      BlogUploadVersionConflict(Failure.networkOffline()),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.myArticleVisibilityConflict), findsOneWidget);
    expect(harness.fetches, 2);
    expect(find.byTooltip(l10n.myArticleActionsTooltip), findsOneWidget);
  });

  testWidgets('a body the app cannot carry is published on the web only', (
    tester,
  ) async {
    final rich = _listed(
      'rich',
      isDraft: true,
      document: ArticleDocument(
        version: 1,
        blocks: [_paragraph('Quoted words', attribution: 'Someone')],
      ),
    );
    final harness = _Harness([rich]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.myArticleActionsTooltip));
    await tester.pumpAndSettle();
    expect(find.text(l10n.myArticleVisibilityWebOnly), findsOneWidget);
    await tester.tap(find.text(l10n.myArticleActionPublish));
    await tester.pumpAndSettle();
    expect(harness.uploads, isEmpty);
  });

  testWidgets('a row without a revision asks for a refresh', (tester) async {
    final harness = _Harness([_blog('plain')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.myArticleActionsTooltip));
    await tester.pumpAndSettle();
    expect(find.text(l10n.myArticleVisibilityRefreshFirst), findsOneWidget);
    await tester.tap(find.text(l10n.editorUnpublishToDraft));
    await tester.pumpAndSettle();
    expect(find.text(l10n.editorUnpublishTitle), findsNothing);
    expect(harness.uploads, isEmpty);
  });
}
