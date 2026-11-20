import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: inner!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _row({VoidCallback? onTap, VoidCallback? onLongPress}) {
  return NoWavePressable(
    onTap: onTap ?? () {},
    onLongPress: onLongPress,
    child: const SizedBox(
      width: 300,
      height: 64,
      child: Row(
        children: [
          Expanded(child: Text('An article')),
          NoWavePressArrow(),
        ],
      ),
    ),
  );
}

Finder _inside(Type type) => find.descendant(
  of: find.byType(NoWavePressable),
  matching: find.byType(type),
);

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(_inside(AnimatedScale)).scale;

Offset _arrowOffset(WidgetTester tester) =>
    tester.widget<AnimatedSlide>(_inside(AnimatedSlide)).offset;

void main() {
  group('NoWavePressArrow.offsetFor', () {
    test('rests at zero', () {
      expect(
        NoWavePressArrow.offsetFor(
          engaged: false,
          direction: TextDirection.ltr,
        ),
        Offset.zero,
      );
    });

    test('steps forward in the reading direction', () {
      final step = NoWaveSizes.arrowNudge / NoWaveIconSize.row;
      expect(
        NoWavePressArrow.offsetFor(engaged: true, direction: TextDirection.ltr),
        Offset(step, 0),
      );
      expect(
        NoWavePressArrow.offsetFor(engaged: true, direction: TextDirection.rtl),
        Offset(-step, 0),
      );
    });
  });

  testWidgets('a press sinks the content and the arrow steps ahead', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_row()));
    expect(_scale(tester), 1);
    expect(_arrowOffset(tester), Offset.zero);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('An article')),
    );
    // InkWell reports the highlight once the tap is no longer ambiguous.
    await tester.pump(kPressTimeout);

    expect(_scale(tester), NoWaveMotion.pressScale);
    expect(_arrowOffset(tester).dx, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(_arrowOffset(tester), Offset.zero);
  });

  testWidgets('taps and long presses still reach the caller', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      _app(_row(onTap: () => taps++, onLongPress: () => longPresses++)),
    );

    await tester.tap(find.text('An article'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('An article'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(longPresses, 1);
  });

  testWidgets('with less motion nothing scales or slides', (tester) async {
    await tester.pumpWidget(_app(_row(), disableAnimations: true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('An article')),
    );
    await tester.pump(kPressTimeout);

    expect(_inside(AnimatedScale), findsNothing);
    expect(_inside(AnimatedSlide), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the arrow is decoration and works outside a pressable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const NoWavePressArrow()));

    expect(find.byType(AnimatedSlide), findsNothing);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.arrow_forward),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });
}
