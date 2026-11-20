import 'package:belog/core/design/components/no_wave_tab_indicator.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar(
  int index, {
  bool disableAnimations = false,
  TextDirection direction = TextDirection.ltr,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 800),
      disableAnimations: disableAnimations,
    ),
    child: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: NoWaveTabIndicator(index: index, count: 4),
        ),
      ),
    ),
  );
}

final _rule = find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == AppPalette.orange,
);

double _ruleCentre(WidgetTester tester) => tester.getCenter(_rule).dx;

void main() {
  test('slots divide the bar evenly from start to end', () {
    expect(NoWaveTabIndicator.alignmentFor(0, 4).start, -1);
    expect(NoWaveTabIndicator.alignmentFor(3, 4).start, 1);
    expect(NoWaveTabIndicator.alignmentFor(1, 4).start, closeTo(-1 / 3, 1e-9));
    // A single destination sits in the middle rather than dividing by zero.
    expect(NoWaveTabIndicator.alignmentFor(0, 1).start, 0);
  });

  testWidgets('the rule is centred over the selected slot', (tester) async {
    await tester.pumpWidget(_bar(0));

    final size = tester.getSize(_rule);
    expect(size.width, NoWaveSizes.tabIndicator);
    expect(size.height, NoWaveSizes.accentRule);
    // Slot 0 of four on a 400pt bar spans 0-100.
    expect(_ruleCentre(tester), 50);
  });

  testWidgets('changing tab moves the rule over time', (tester) async {
    await tester.pumpWidget(_bar(0));
    await tester.pumpWidget(_bar(2));

    // Half-way through the motion the rule is between the two slots.
    await tester.pump(NoWaveMotion.normal ~/ 2);
    final midway = _ruleCentre(tester);
    expect(midway, greaterThan(50));
    expect(midway, lessThan(250));

    await tester.pumpAndSettle();
    expect(_ruleCentre(tester), 250);
  });

  testWidgets('with less motion the rule is placed, not moved', (tester) async {
    await tester.pumpWidget(_bar(0, disableAnimations: true));
    await tester.pumpWidget(_bar(3, disableAnimations: true));
    await tester.pump();

    expect(_ruleCentre(tester), 350);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a right-to-left bar starts on the right', (tester) async {
    await tester.pumpWidget(_bar(0, direction: TextDirection.rtl));

    expect(_ruleCentre(tester), 350);
  });

  testWidgets('the rule is decoration', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_bar(1));

    expect(
      find.descendant(
        of: find.byType(NoWaveTabIndicator),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NoWaveTabIndicator),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
