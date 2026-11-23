import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
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
        GoRoute(path: '/', builder: (_, _) => const UserBlogsPage()),
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
  setUpAll(() => registerFallbackValue(GetMyArticlesEvent(userId: 'x')));

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
    expect(harness.opened, [null]);

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
    expect(harness.opened.single, same(plain));
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

  testWidgets('every article row offers deletion', (tester) async {
    final harness = _Harness([_blog('one'), _blog('two')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byTooltip(l10n.deleteArticleTitle), findsNWidgets(2));
  });
}
