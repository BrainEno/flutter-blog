import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/pages/saved_blogs_page.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness, sampleBlog, sampleUser;

/// The reported bug: open the saved tab once (empty), save an article from
/// the home tab, come back to the saved tab - it still said "you have not
/// saved any articles". The tab is kept alive with the list it first read.
void main() {
  setUp(() => GetIt.instance.reset());

  testWidgets('an article saved in the home tab shows up in the saved tab '
      'that was already open', (tester) async {
    final harness = Harness()..buildRouter();
    addTearDown(harness.dispose);
    final article = sampleBlog('1', '第一篇文章');
    var saved = <BlogModel>[];
    when(
      () => harness.remote.getAllBlogs(page: 1),
    ).thenAnswer((_) async => [article]);
    when(
      () => harness.remote.getBlogById(any()),
    ).thenAnswer((_) async => article);
    when(
      () => harness.remote.getUserLikedBlogs(any()),
    ).thenAnswer((_) async => saved);
    when(
      () => harness.remote.isBlogLikedByUser(any(), any()),
    ).thenAnswer((_) async => saved.isNotEmpty);
    when(() => harness.remote.toggleLikeBlog(any(), any())).thenAnswer((
      _,
    ) async {
      saved = [article];
      return true;
    });
    harness.appUserCubit.updateUser(sampleUser());
    await harness.pump(tester);
    await tester.pumpAndSettle();

    // The saved tab, visited first: nothing saved yet.
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedBlogsPage), findsOneWidget);
    expect(find.text('你还没有收藏文章'), findsOneWidget);

    // Home, open the article, save it.
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(BlogCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BlogCard));
    await tester.pumpAndSettle();
    expect(find.byType(BlogViewerPage), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BlogViewerPage),
        matching: find.byTooltip('收藏'),
      ),
    );
    await tester.pumpAndSettle();
    verify(() => harness.remote.toggleLikeBlog(any(), '1')).called(1);

    // Back to the saved tab: the article is there.
    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(find.byType(SavedBlogsPage), findsOneWidget);
    expect(find.text('你还没有收藏文章'), findsNothing);
    expect(find.byType(BlogGridItem), findsOneWidget);
  });
}
