import 'package:belog/features/blog/presentation/widgets/article_tag_label.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget label) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: Wrap(children: [label]))),
    ),
  );
}

void main() {
  testWidgets('without a callback the label stays inert', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ArticleTagLabel(tag: '诗歌'));

    expect(find.text('诗歌'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(
      tester.getSemantics(find.byType(ArticleTagLabel)).hasFlag(
        SemanticsFlag.isButton,
      ),
      isFalse,
      reason: '不可点的标签不该被读屏当成按钮',
    );
    handle.dispose();
  });

  testWidgets('with a callback it is a labelled button with a real target', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(
      tester,
      ArticleTagLabel(tag: '诗歌', onTap: () => taps += 1),
    );

    final size = tester.getSize(find.byType(TextButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    final node = tester.getSemantics(find.byType(ArticleTagLabel));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.hasTapAction), isTrue);
    expect(node.label, '浏览标签「诗歌」的文章');
    expect(
      find.text('诗歌'),
      findsOneWidget,
      reason: '视觉上仍是原来的小标签',
    );

    await tester.tap(find.byType(TextButton));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('the chip keeps its compact drawn size', (tester) async {
    await _pump(tester, ArticleTagLabel(tag: '诗歌', onTap: () {}));

    final chip = tester.getSize(
      find
          .descendant(
            of: find.byType(TextButton),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(chip.height, lessThan(32), reason: '点击目标变大，外观不变');
  });
}
