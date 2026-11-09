import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/presentation/widgets/article_category_label.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/features/blog/presentation/widgets/article_tag_label.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the header the way a page does: inside something that scrolls. The
/// header is a plain Column, so it needs room it can grow into.
Future<void> _pumpHeader(WidgetTester tester, ArticleReaderHeader header) =>
    _pump(tester, SingleChildScrollView(child: header));

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Blog _blog({
  List<CategoryRef> categories = const [],
  List<String> tags = const [],
}) => Blog(
  id: 'a-slug',
  title: '标题',
  content: '正文',
  posterId: 'author',
  imageUrl: '',
  tags: tags,
  updatedAt: DateTime.utc(2026, 10, 1),
  categories: categories,
);

const _essay = CategoryRef(id: 'cat-1', slug: 'essay', name: '随笔');

void main() {
  testWidgets('a category without a callback stays inert', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const Center(child: ArticleCategoryLabel(category: _essay)),
    );

    expect(find.text('随笔'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    final data = tester
        .getSemantics(find.byType(ArticleCategoryLabel))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('with a callback it is a labelled button with a real target', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(
      tester,
      Center(
        child: ArticleCategoryLabel(category: _essay, onTap: () => taps += 1),
      ),
    );

    final size = tester.getSize(find.byType(TextButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    final data = tester
        .getSemantics(find.byType(ArticleCategoryLabel))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.label, '浏览分类「随笔」的文章');

    await tester.tap(find.byType(TextButton));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('the article header draws its categories above its tags', (
    tester,
  ) async {
    var opened = <String>[];
    await _pumpHeader(
      tester,
      ArticleReaderHeader(
        blog: _blog(
          categories: const [
            _essay,
            CategoryRef(id: 'cat-2', slug: 'poem', name: '诗'),
          ],
          tags: const ['诗歌'],
        ),
        onAuthorTap: () {},
        onTagTap: opened.add,
        onCategoryTap: (category) => opened.add(category.slug),
      ),
    );

    expect(find.byType(ArticleCategoryLabel), findsNWidgets(2));
    expect(find.byType(ArticleTagLabel), findsOneWidget);
    // A category is editorial structure and a tag is the author's word; they
    // are different widgets on purpose, and both come before the title.
    expect(
      tester.getTopLeft(find.byType(ArticleTagLabel)).dy,
      greaterThan(tester.getTopLeft(find.text('诗')).dy),
    );

    await tester.tap(find.text('随笔'));
    await tester.pump();
    expect(opened, ['essay']);
  });

  testWidgets('a category with no address is not drawn', (tester) async {
    // A cache row written before names were kept carries ids alone.
    await _pumpHeader(
      tester,
      ArticleReaderHeader(
        blog: _blog(
          categories: const [
            CategoryRef(id: 'cat-1', slug: '', name: ''),
            _essay,
          ],
        ),
        onAuthorTap: () {},
        onCategoryTap: (_) {},
      ),
    );

    expect(find.byType(ArticleCategoryLabel), findsOneWidget);
    expect(find.text('随笔'), findsOneWidget);
  });

  testWidgets('an article with no categories draws no row at all', (
    tester,
  ) async {
    await _pumpHeader(
      tester,
      ArticleReaderHeader(
        blog: _blog(tags: const ['诗歌']),
        onAuthorTap: () {},
        onCategoryTap: (_) {},
      ),
    );

    expect(find.byType(ArticleCategoryLabel), findsNothing);
    expect(find.byType(ArticleTagLabel), findsOneWidget);
  });
}
