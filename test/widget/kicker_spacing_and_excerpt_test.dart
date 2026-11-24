import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/presentation/widgets/article_category_label.dart';
import 'package:belog/features/blog/presentation/widgets/article_tag_label.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// The visible gap between two words of a row: from where one word's ink
/// ends to where the next one's starts.
double _gap(WidgetTester tester, String before, String after) =>
    tester.getTopLeft(find.text(after)).dx -
    tester.getTopRight(find.text(before)).dx;

const _essay = CategoryRef(id: 'cat-1', slug: 'essay', name: '随笔');

/// A two-character word, a long word and a Latin word: their 48pt targets
/// are fitted, overfilled and overfilled again by very different amounts.
const _tags = ['诗歌', '一座城市的夜晚', 'Flutter'];

void main() {
  testWidgets('every word of a tappable kicker is followed by the same gap', (
    tester,
  ) async {
    await _pump(
      tester,
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ArticleCategoryLabel(category: _essay, quiet: true, onTap: () {}),
          for (final tag in _tags)
            ArticleTagLabel(tag: tag, quiet: true, onTap: () {}),
        ],
      ),
    );

    final gaps = [
      _gap(tester, '随笔', _tags[0]),
      _gap(tester, _tags[0], _tags[1]),
      _gap(tester, _tags[1], _tags[2]),
    ];
    for (final gap in gaps) {
      expect(gap, closeTo(NoWaveSpacing.kickerWord, 0.5));
    }
    // The spacing did not cost the target: each word is still a 48pt button.
    for (final button in tester.widgetList(find.byType(TextButton))) {
      final size = tester.getSize(find.byWidget(button));
      expect(size.width, greaterThanOrEqualTo(NoWaveSizes.tapTarget));
      expect(size.height, greaterThanOrEqualTo(NoWaveSizes.tapTarget));
    }
  });

  testWidgets('an inert kicker reads with the same gap as a tappable one', (
    tester,
  ) async {
    await _pump(
      tester,
      Wrap(
        children: [
          const ArticleCategoryLabel(category: _essay, quiet: true),
          for (final tag in _tags) ArticleTagLabel(tag: tag, quiet: true),
        ],
      ),
    );

    expect(
      _gap(tester, '随笔', _tags[0]),
      closeTo(NoWaveSpacing.kickerWord, 0.5),
    );
    expect(
      _gap(tester, _tags[1], _tags[2]),
      closeTo(NoWaveSpacing.kickerWord, 0.5),
    );
  });

  testWidgets('a card row keeps its tags evenly apart and the date after', (
    tester,
  ) async {
    await _pump(
      tester,
      BlogCard(
        blog: Blog(
          id: 'row',
          title: '标题',
          content: '正文',
          posterId: 'author',
          imageUrl: '',
          tags: const ['诗歌', '一座城市的夜晚'],
          updatedAt: DateTime.utc(2026, 10, 31),
        ),
        index: 2,
        onTap: () {},
        onTagTap: (_) {},
      ),
    );

    expect(
      _gap(tester, '诗歌', '一座城市的夜晚'),
      closeTo(NoWaveSpacing.kickerWord, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  group('list excerpt', () {
    // An author-written summary may run to 2000 characters; a list shows a
    // few lines of it, then an ellipsis.
    final longSummary = List.filled(40, '作者自己写的摘要会很长，一行接一行地写下去。').join();

    Blog withSummary() => Blog(
      id: 'long-summary',
      title: '一篇摘要很长的文章',
      content: '正文与摘要不同，所以列表显示作者写的摘要。',
      summary: longSummary,
      posterId: 'author',
      imageUrl: '',
      tags: const [],
      updatedAt: DateTime.utc(2026, 10, 31),
    );

    Future<Text> excerptOf(WidgetTester tester, BlogCard card) async {
      await _pump(tester, card);
      final finder = find.byKey(const ValueKey('blog-card-excerpt'));
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      final style = text.style!;
      final lineHeight = style.fontSize! * style.height!;
      expect(
        tester.getSize(finder).height,
        lessThanOrEqualTo(lineHeight * text.maxLines! + 1),
      );
      return text;
    }

    testWidgets('a row shows three lines and ends in an ellipsis', (
      tester,
    ) async {
      final text = await excerptOf(
        tester,
        BlogCard(blog: withSummary(), index: 2, onTap: () {}),
      );
      expect(text.maxLines, AppLimits.excerptRowLines);
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the lead story may take one more line', (tester) async {
      final text = await excerptOf(
        tester,
        BlogCard(blog: withSummary(), featured: true, index: 1, onTap: () {}),
      );
      expect(text.maxLines, AppLimits.excerptLeadLines);
      expect(text.maxLines, AppLimits.excerptRowLines + 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });
}
