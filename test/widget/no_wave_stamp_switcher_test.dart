import 'package:belog/core/design/components/no_wave_stamp_switcher.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _toggle(bool saved, {bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: inner!,
    ),
    home: Scaffold(
      body: Center(
        child: NoWaveStampSwitcher(
          child: Icon(
            saved ? Icons.bookmark : Icons.bookmark_border,
            key: ValueKey(saved),
          ),
        ),
      ),
    ),
  );
}

double _scaleOf(WidgetTester tester, IconData icon) {
  final transition = tester.widget<ScaleTransition>(
    find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(ScaleTransition),
    ),
  );
  return transition.scale.value;
}

void main() {
  testWidgets('a new state lands large and settles', (tester) async {
    await tester.pumpWidget(_toggle(false));
    await tester.pumpWidget(_toggle(true));

    // The first frame of the stamp: the new glyph is at its largest.
    expect(_scaleOf(tester, Icons.bookmark), NoWaveMotion.stampScale);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.pumpAndSettle();
    expect(_scaleOf(tester, Icons.bookmark), 1);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });

  testWidgets('a rebuild in the same state does not stamp', (tester) async {
    await tester.pumpWidget(_toggle(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_toggle(true));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with less motion the glyph swaps in one frame', (tester) async {
    await tester.pumpWidget(_toggle(false, disableAnimations: true));
    await tester.pumpWidget(_toggle(true, disableAnimations: true));

    expect(
      find.descendant(
        of: find.byType(NoWaveStampSwitcher),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });
}
