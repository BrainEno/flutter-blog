import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness, sampleUser;

/// Remembers what the reader asked it to keep, so a test can tell a preview
/// from a read.
class _History implements ReadingHistoryStore {
  final recorded = <String>[];
  final saved = <double>[];

  @override
  Future<void> record({required String userId, required Blog blog}) async {
    recorded.add(blog.id);
  }

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async => const [];

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async => saved.add(progress);

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) async => null;

  @override
  Future<void> remove({required String userId, required String blogId}) async {}

  @override
  Future<void> clear({required String userId}) async {}
}

const _paragraph =
    '夜里的城市像一张没有写完的稿纸。路灯一盏一盏亮起来，把街道切成整齐的段落，'
    '而我们只是其中被反复修改的句子。';

BlogModel _article({
  required bool isDraft,
  String title = '没有写完的稿纸',
  String posterId = 'user',
}) => BlogModel(
  id: 'piece',
  title: title,
  content: [for (var i = 0; i < 12; i++) _paragraph].join('\n\n'),
  posterId: posterId,
  imageUrl: '',
  tags: const ['散文'],
  updatedAt: DateTime.utc(2026, 11),
  isDraft: isDraft,
);

void main() {
  setUp(() => GetIt.instance.reset());

  /// The real app router, so the end matter, app bar and history wiring are
  /// the ones a reader gets.
  Future<(Harness, _History)> openInApp(
    WidgetTester tester,
    BlogModel article,
  ) async {
    final harness = Harness()..buildRouter(initialLocation: '/view/piece');
    addTearDown(harness.dispose);
    final history = _History();
    GetIt.instance.registerSingleton<ReadingHistoryStore>(history);
    when(
      () => harness.remote.getBlogById(any()),
    ).thenAnswer((_) async => article);
    when(
      () => harness.remote.isBlogLikedByUser(any(), any()),
    ).thenAnswer((_) async => false);
    harness.appUserCubit.updateUser(sampleUser());
    await harness.pump(tester);
    await tester.pumpAndSettle();
    return (harness, history);
  }

  testWidgets('a draft opens as a preview: no saving, comments or related', (
    tester,
  ) async {
    final (harness, history) = await openInApp(tester, _article(isDraft: true));

    expect(find.byType(BlogViewerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-draft-notice')), findsOneWidget);
    expect(find.text('草稿预览，只有你看得到；发布后才会显示收藏、评论和相关阅读。'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.byKey(const ValueKey('article-end-matter')), findsNothing);
    expect(find.byType(CommentsSection), findsNothing);
    expect(find.byType(RelatedArticlesSection), findsNothing);

    // Scrolling through the preview is checking, not reading.
    await tester.drag(find.byType(BlogViewerPage), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(history.recorded, isEmpty);
    expect(history.saved, isEmpty);
    verifyNever(() => harness.remote.isBlogLikedByUser(any(), any()));
    verifyNever(() => harness.remote.getRelatedArticles(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a published article keeps its saving, comments and history', (
    tester,
  ) async {
    final (_, history) = await openInApp(tester, _article(isDraft: false));

    expect(find.byKey(const ValueKey('reader-draft-notice')), findsNothing);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byKey(const ValueKey('article-end-matter')), findsOneWidget);
    expect(history.recorded, ['piece']);
  });

  testWidgets("someone else's draft gets the note but no edit button", (
    tester,
  ) async {
    await openInApp(tester, _article(isDraft: true, posterId: 'other'));

    expect(find.byKey(const ValueKey('reader-draft-notice')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NoWaveNotice), matching: find.text('编辑')),
      findsNothing,
    );
  });

  for (final (branch, viewPath, editorPath) in const [
    ('feed', '/view/piece', '/editor'),
    ('profile', '/profile/view/piece', '/profile/editor'),
  ]) {
    testWidgets(
      'editing a draft from the $branch branch reloads the preview on save',
      (tester) async {
        // The services come from the app's registrations; the router is a
        // small one, so the editor can be a stub that answers "saved".
        final harness = Harness();
        addTearDown(harness.dispose);
        var current = _article(isDraft: true);
        when(
          () => harness.remote.getBlogById(any()),
        ).thenAnswer((_) async => current);
        harness.appUserCubit.updateUser(sampleUser());
        final opened = <(String, Object?)>[];

        Widget viewer(GoRouterState state) => MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => GetIt.instance<BlogLikedBloc>()),
            BlocProvider(
              create: (_) => BlogViewerCubit(
                getBlogById: GetIt.instance<GetBlogById>(),
                blogId: state.pathParameters['id']!,
              ),
            ),
          ],
          child: BlogViewerPage(
            blogId: state.pathParameters['id']!,
            historyStore: _History(),
          ),
        );

        Widget editor(GoRouterState state) => Builder(
          builder: (context) {
            opened.add((state.uri.path, state.extra));
            return Scaffold(
              body: TextButton(
                onPressed: () => context.pop(true),
                child: const Text('save stub'),
              ),
            );
          },
        );

        final router = GoRouter(
          initialLocation: viewPath,
          routes: [
            GoRoute(path: '/view/:id', builder: (_, s) => viewer(s)),
            GoRoute(path: '/editor', builder: (_, s) => editor(s)),
            GoRoute(path: '/profile/view/:id', builder: (_, s) => viewer(s)),
            GoRoute(path: '/profile/editor', builder: (_, s) => editor(s)),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          BlocProvider<AppUserCubit>.value(
            value: harness.appUserCubit,
            child: MaterialApp.router(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('没有写完的稿纸'), findsWidgets);

        await tester.tap(
          find.descendant(
            of: find.byType(NoWaveNotice),
            matching: find.text('编辑'),
          ),
        );
        await tester.pumpAndSettle();
        expect(opened, isNotEmpty);
        expect(opened.last.$1, editorPath);
        expect((opened.last.$2! as Blog).id, 'piece');

        current = _article(isDraft: true, title: '改过的标题');
        await tester.tap(find.text('save stub'));
        await tester.pumpAndSettle();

        expect(find.byType(BlogViewerPage), findsOneWidget);
        expect(find.text('改过的标题'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
