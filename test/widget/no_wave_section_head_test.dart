import 'package:belog/core/design/components/no_wave_section_head.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _head({String? trailing, double textScale = 1, double width = 360}) =>
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
              child: Column(
                children: [
                  NoWaveSectionHead(title: 'Comments', trailing: trailing),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('no rule: the title is told from the rows by size and space', (
    tester,
  ) async {
    await tester.pumpWidget(_head());

    final headFinder = find.byKey(const ValueKey('no-wave-section-head'));
    expect(
      find.descendant(of: headFinder, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    final head = tester.getRect(headFinder);
    final title = tester.getRect(find.text('Comments'));
    expect(title.top, closeTo(head.top, 0.5));
    expect(head.bottom - title.bottom, closeTo(NoWaveSpacing.medium, 0.5));
    expect(
      tester.widget<Text>(find.text('Comments')).style?.fontSize,
      NoWaveTypeScale.dialogTitle,
    );
  });

  testWidgets('the count sits flush right on the title baseline', (
    tester,
  ) async {
    await tester.pumpWidget(_head(trailing: '3 loaded'));

    final head = tester.getRect(
      find.byKey(const ValueKey('no-wave-section-head')),
    );
    final title = tester.getRect(find.text('Comments'));
    final count = tester.getRect(find.text('3 loaded'));
    expect(count.right, closeTo(head.right, 0.5));
    expect(title.left, closeTo(head.left, 0.5));
    expect(
      count.left - title.right,
      greaterThanOrEqualTo(NoWaveSpacing.medium),
    );

    final row = tester.widget<Row>(
      find.descendant(
        of: find.byKey(const ValueKey('no-wave-section-head')),
        matching: find.byType(Row),
      ),
    );
    expect(row.crossAxisAlignment, CrossAxisAlignment.baseline);
    expect(row.textBaseline, TextBaseline.alphabetic);
  });

  testWidgets('a long title at twice the text size does not overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _head(trailing: '128 loaded', textScale: 2, width: 320),
    );
    expect(tester.takeException(), isNull);
  });
}
