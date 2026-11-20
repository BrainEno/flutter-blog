import 'package:belog/core/design/components/no_wave_reading_progress.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page({
  required ScrollController controller,
  int rows = 100,
  Widget? row,
}) {
  return MaterialApp(
    home: Scaffold(
      body: NoWaveReadingProgress(
        child: ListView.builder(
          controller: controller,
          itemCount: rows,
          itemExtent: 50,
          itemBuilder: (context, index) => row ?? Text('row $index'),
        ),
      ),
    ),
  );
}

final _fill = find.descendant(
  of: find.byType(NoWaveReadingProgress),
  matching: find.byType(FractionallySizedBox),
);

double _fraction(WidgetTester tester) =>
    tester.widget<FractionallySizedBox>(_fill).widthFactor!;

ScrollMetrics _metrics({
  required double pixels,
  double min = 0,
  double max = 1000,
}) => FixedScrollMetrics(
  minScrollExtent: min,
  maxScrollExtent: max,
  pixels: pixels,
  viewportDimension: 600,
  axisDirection: AxisDirection.down,
  devicePixelRatio: 1,
);

void main() {
  group('fractionOf', () {
    test('reads the share of the scroll extent', () {
      expect(NoWaveReadingProgress.fractionOf(_metrics(pixels: 0)), 0);
      expect(NoWaveReadingProgress.fractionOf(_metrics(pixels: 250)), .25);
      expect(NoWaveReadingProgress.fractionOf(_metrics(pixels: 1000)), 1);
    });

    test('overscroll stays inside the bar', () {
      expect(NoWaveReadingProgress.fractionOf(_metrics(pixels: -80)), 0);
      expect(NoWaveReadingProgress.fractionOf(_metrics(pixels: 1080)), 1);
    });

    test('a page that does not scroll is unread', () {
      expect(NoWaveReadingProgress.fractionOf(_metrics(pixels: 0, max: 0)), 0);
    });

    test('a non-zero minimum extent is measured from the top', () {
      expect(
        NoWaveReadingProgress.fractionOf(
          _metrics(pixels: 150, min: 100, max: 300),
        ),
        .25,
      );
    });
  });

  testWidgets('the line fills as the page scrolls', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_page(controller: controller));

    expect(_fraction(tester), 0);
    expect(tester.getSize(_fill).height, NoWaveSizes.accentRule);

    final max = controller.position.maxScrollExtent;
    controller.jumpTo(max / 2);
    await tester.pump();
    expect(_fraction(tester), closeTo(.5, 1e-9));

    controller.jumpTo(max);
    await tester.pump();
    expect(_fraction(tester), 1);
  });

  testWidgets('a nested sideways scroller does not move the line', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _page(
        controller: controller,
        row: SingleChildScrollView(
          key: const ValueKey('code'),
          scrollDirection: Axis.horizontal,
          child: Text('x' * 400),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('code')).first,
      const Offset(-300, 0),
    );
    await tester.pump();

    expect(_fraction(tester), 0);
  });

  testWidgets('the line does not take taps or semantics', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_page(controller: controller));

    for (final type in [IgnorePointer, ExcludeSemantics]) {
      expect(
        find.ancestor(of: _fill, matching: find.byType(type)),
        findsWidgets,
      );
    }
    // The page underneath still scrolls from a drag that starts under it.
    await tester.dragFrom(const Offset(200, 1), const Offset(0, -200));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
  });
}
