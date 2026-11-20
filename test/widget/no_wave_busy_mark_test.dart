import 'package:belog/core/design/components/no_wave_busy_mark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test('the segment enters before the start and leaves past the end', () {
    expect(NoWaveBusyMark.segmentStart(0), -NoWaveSizes.busySegment);
    expect(NoWaveBusyMark.segmentStart(1), closeTo(1, 1e-9));
    expect(
      NoWaveBusyMark.segmentStart(0.5),
      closeTo((1 - NoWaveSizes.busySegment) / 2, 1e-9),
      reason: 'half way through a pass it is centred',
    );
  });

  testWidgets('fills the icon slot it stands in for, and keeps moving', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const NoWaveBusyMark()));
    expect(
      tester.getSize(find.byType(NoWaveBusyMark)),
      const Size.square(NoWaveIconSize.inline),
    );
    await tester.pump(NoWaveMotion.normal);
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('is silent unless it is the only thing in its slot', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NoWaveBusyMark(key: ValueKey('quiet')),
            NoWaveBusyMark(
              key: ValueKey('labelled'),
              size: NoWaveIconSize.row,
              semanticsLabel: 'Loading',
            ),
          ],
        ),
      ),
    );

    final labelled = find.bySemanticsLabel('Loading');
    expect(labelled, findsOneWidget);
    expect(
      tester
          .getSemantics(labelled)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('labelled'))),
      const Size.square(NoWaveIconSize.row),
    );
    handle.dispose();
  });

  testWidgets('with less motion the segment rests', (tester) async {
    await tester.pumpWidget(
      _app(const NoWaveBusyMark(), disableAnimations: true),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
