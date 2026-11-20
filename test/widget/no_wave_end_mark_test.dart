import 'package:belog/core/design/components/no_wave_end_mark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _square = ValueKey('no-wave-end-mark');

Widget _mark({String? byline, double textScale = 1, double width = 400}) =>
    MaterialApp(
      theme: AppTheme.lightThemeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: NoWaveEndMark(label: 'The end', byline: byline),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('an orange square centred between two hairlines', (tester) async {
    await tester.pumpWidget(_mark());

    final square = tester.getRect(find.byKey(_square));
    expect(square.size, const Size.square(NoWaveSizes.endMark));
    expect(
      square.center.dx,
      closeTo(tester.getRect(find.byType(NoWaveEndMark)).center.dx, 1),
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(_square),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      AppPalette.orange,
    );
    final lines = find.descendant(
      of: find.byType(NoWaveEndMark),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.height == NoWaveStroke.hairline,
      ),
    );
    expect(lines, findsNWidgets(2));
    expect(tester.getRect(lines.first).right, lessThan(square.left));
    expect(tester.getRect(lines.last).left, greaterThan(square.right));
  });

  testWidgets('the colophon is read as written; the ornament is not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_mark(byline: 'Words by Ada'));

    expect(find.text('The end · Words by Ada'), findsOneWidget);
    expect(find.bySemanticsLabel('The end · Words by Ada'), findsOneWidget);
    final text = tester.getRect(find.text('The end · Words by Ada'));
    expect(text.top, greaterThan(tester.getRect(find.byKey(_square)).bottom));
    handle.dispose();
  });

  testWidgets('without an author it just says it ended', (tester) async {
    await tester.pumpWidget(_mark());
    expect(find.text('The end'), findsOneWidget);
  });

  testWidgets('wraps at 2x on a narrow screen', (tester) async {
    await tester.pumpWidget(
      _mark(
        byline: 'Words by a writer with a long name',
        textScale: 2,
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
