import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rule = ValueKey('no-wave-eyebrow-rule');

Widget _heading({String? eyebrow, double textScale = 1, double width = 400}) =>
    MaterialApp(
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

  testWidgets('no eyebrow, no rule', (tester) async {
    await tester.pumpWidget(_heading());
    expect(find.byType(NoWaveEyebrow), findsNothing);
    expect(find.byKey(_rule), findsNothing);
  });

  testWidgets('the eyebrow is a short orange rule and tracked capitals', (
    tester,
  ) async {
    await tester.pumpWidget(_heading(eyebrow: 'Downloaded to this device'));

    final rule = tester.getRect(find.byKey(_rule));
    expect(rule.width, NoWaveSizes.eyebrowRule);
    expect(rule.height, NoWaveSizes.accentRule);
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(_rule),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      AppPalette.orange,
    );

    final words = find.text('DOWNLOADED TO THIS DEVICE');
    expect(words, findsOneWidget);
    final style = tester.widget<Text>(words).style!;
    expect(style.fontSize, NoWaveTypeScale.eyebrow);
    expect(style.letterSpacing, greaterThan(NoWaveTypeScale.eyebrow * 0.1));

    // Above the title, starting at the same edge, rule first.
    final text = tester.getRect(words);
    final title = tester.getRect(find.text('Latest'));
    expect(text.bottom, lessThanOrEqualTo(title.top));
    expect(rule.left, closeTo(title.left, 1));
    expect(text.left, greaterThan(rule.right));
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
