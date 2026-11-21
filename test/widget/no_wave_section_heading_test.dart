import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _heading({
  String? eyebrow,
  String? aside,
  double textScale = 1,
  double width = 400,
}) => MaterialApp(
  theme: AppTheme.lightThemeMode,
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: NoWaveSectionHeading(
            title: 'Latest',
            companion: 'Works',
            eyebrow: eyebrow,
            aside: aside,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('NoWaveEyebrow.isCjk', () {
    test('tells Chinese from Latin', () {
      expect(NoWaveEyebrow.isCjk('独立文学出版 · 阅读与交流'), isTrue);
      expect(NoWaveEyebrow.isCjk('作品目录'), isTrue);
      expect(NoWaveEyebrow.isCjk('Independent literary publishing'), isFalse);
      expect(NoWaveEyebrow.isCjk('2026 · 12'), isFalse);
    });

    test('capitals for Latin, Chinese unchanged', () {
      expect(NoWaveEyebrow.displayText('Bibliography'), 'BIBLIOGRAPHY');
      expect(NoWaveEyebrow.displayText('作品目录'), '作品目录');
    });
  });

  testWidgets('no eyebrow, nothing above the title', (tester) async {
    await tester.pumpWidget(_heading());
    expect(find.byType(NoWaveEyebrow), findsNothing);
  });

  testWidgets('the eyebrow is tracked capitals alone, with no rule', (
    tester,
  ) async {
    await tester.pumpWidget(_heading(eyebrow: 'Downloaded to this device'));

    expect(
      find.descendant(
        of: find.byType(NoWaveEyebrow),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );

    final words = find.text('DOWNLOADED TO THIS DEVICE');
    expect(words, findsOneWidget);
    final style = tester.widget<Text>(words).style!;
    expect(style.fontSize, NoWaveTypeScale.eyebrow);
    expect(style.letterSpacing, greaterThan(NoWaveTypeScale.eyebrow * 0.1));

    // Above the title, starting at the same edge.
    final text = tester.getRect(words);
    final title = tester.getRect(find.textContaining('Latest'));
    expect(text.bottom, lessThanOrEqualTo(title.top));
    expect(text.left, closeTo(title.left, 1));
  });

  testWidgets('the title and its gloss are one line of type', (tester) async {
    await tester.pumpWidget(_heading());

    // One paragraph, so the two share a baseline and wrap as words.
    final heading = find.text('Latest Works');
    expect(heading, findsOneWidget);
    final span = tester.widget<Text>(heading).textSpan! as TextSpan;
    final gloss = span.children!.last as TextSpan;
    expect(gloss.text, 'Works');
    expect(gloss.style!.fontStyle, FontStyle.italic);
    expect(
      gloss.style!.color,
      AppTheme.lightThemeMode.colorScheme.onSurfaceVariant,
    );
    expect(
      tester.widget<Text>(heading).style!.fontSize,
      NoWaveTypeScale.heading,
    );
  });

  testWidgets('a short heading starts at the edge, not in the middle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _heading(eyebrow: 'Independent literary publishing', width: 400),
    );
    expect(tester.getRect(find.text('Latest Works')).left, closeTo(0, 1));
  });

  testWidgets('the aside sits at the far end of the eyebrow line', (
    tester,
  ) async {
    await tester.pumpWidget(_heading(eyebrow: 'Edition', aside: 'Thu, Nov 19'));

    final eyebrow = tester.getRect(find.text('EDITION'));
    final aside = tester.getRect(find.text('Thu, Nov 19'));
    expect(aside.right, closeTo(400, 1));
    expect(aside.bottom, closeTo(eyebrow.bottom, 2));
    expect(eyebrow.left, closeTo(0, 1));
  });

  testWidgets('a long aside drops under the eyebrow at 2x', (tester) async {
    await tester.pumpWidget(
      _heading(
        eyebrow: 'Independent literary publishing',
        aside: 'Thursday, November 19',
        textScale: 2,
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese keeps its characters and tracks less', (tester) async {
    await tester.pumpWidget(_heading(eyebrow: '作品目录'));
    final latin = NoWaveTypeScale.eyebrow * 0.1;
    final style = tester.widget<Text>(find.text('作品目录')).style!;
    expect(style.letterSpacing, lessThan(latin));
    expect(style.letterSpacing, greaterThan(0));
  });

  testWidgets('screen readers hear the words as written', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_heading(eyebrow: 'Bibliography'));

    expect(find.bySemanticsLabel('Bibliography'), findsOneWidget);
    expect(find.bySemanticsLabel('BIBLIOGRAPHY'), findsNothing);
    handle.dispose();
  });

  testWidgets('a long eyebrow wraps at 2x on a narrow screen', (tester) async {
    await tester.pumpWidget(
      _heading(
        eyebrow: 'By title, or browse tags and categories',
        textScale: 2,
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
    final text = tester.getRect(
      find.text('BY TITLE, OR BROWSE TAGS AND CATEGORIES'),
    );
    expect(text.right, lessThanOrEqualTo(320));
    expect(text.height, greaterThan(NoWaveTypeScale.eyebrow * 2 * 1.5));
  });
}
