import 'dart:async';

import 'package:belog/core/design/components/no_wave_refresh.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rule = ValueKey('no-wave-refresh-rule');
const _segment = ValueKey('no-wave-refresh-segment');

Widget _list({
  required Future<void> Function() onRefresh,
  bool disableAnimations = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(
      body: NoWaveRefresh(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 3; i++)
              SizedBox(height: NoWaveSizes.row, child: Text('row $i')),
          ],
        ),
      ),
    ),
  ),
);

/// Pulls the list down by [distance] in steps, without letting go.
Future<TestGesture> _pull(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
  );
  // Past the touch slop first, so the scroll view starts a drag.
  await gesture.moveBy(const Offset(0, 30));
  await tester.pump();
  var moved = 0.0;
  while (moved < distance) {
    await gesture.moveBy(const Offset(0, 10));
    moved += 10;
    await tester.pump();
  }
  return gesture;
}

void _expectNoSpinner() {
  expect(find.byType(RefreshProgressIndicator), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void main() {
  group('pullProgress', () {
    test('is 0 at rest and 1 where letting go refreshes', () {
      expect(NoWaveRefresh.pullProgress(0, 600), 0);
      // A quarter of the viewport: 150 of 600.
      expect(NoWaveRefresh.pullProgress(75, 600), closeTo(0.5, 0.001));
      expect(NoWaveRefresh.pullProgress(150, 600), 1);
      expect(NoWaveRefresh.pullProgress(400, 600), 1);
      expect(NoWaveRefresh.pullProgress(10, 0), 0);
    });
  });

  testWidgets('a pull grows a rule, arms orange, then runs a segment', (
    tester,
  ) async {
    final pending = Completer<void>();
    var refreshes = 0;
    await tester.pumpWidget(
      _list(
        onRefresh: () {
          refreshes++;
          return pending.future;
        },
      ),
    );
    expect(find.byKey(_rule), findsNothing, reason: 'nothing at rest');

    final gesture = await _pull(tester, 30);
    final growing = tester.getSize(find.byKey(_rule));
    expect(growing.height, NoWaveSizes.accentRule);
    expect(growing.width, greaterThan(0));
    expect(growing.width, lessThan(800));
    expect(
      tester.widget<ColoredBox>(find.byKey(_rule)).color,
      isNot(AppPalette.orange),
      reason: 'not armed yet',
    );
    // It grows from the centre.
    expect(tester.getCenter(find.byKey(_rule)).dx, closeTo(400, 1));
    _expectNoSpinner();

    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    expect(tester.getSize(find.byKey(_rule)).width, 800);
    expect(
      tester.widget<ColoredBox>(find.byKey(_rule)).color,
      AppPalette.orange,
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(NoWaveMotion.normal);
    expect(refreshes, 1);
    await tester.pump(NoWaveMotion.slow);
    expect(find.byKey(_segment), findsOneWidget);
    final segment = tester.getSize(find.byKey(_segment));
    expect(segment.width, closeTo(800 * NoWaveSizes.refreshSegment, 1));
    _expectNoSpinner();

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_rule), findsNothing);
    expect(find.byKey(_segment), findsNothing);
  });

  testWidgets('a short pull is let go without refreshing', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(_list(onRefresh: () async => refreshes++));

    final gesture = await _pull(tester, 20);
    expect(find.byKey(_rule), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(refreshes, 0);
    expect(find.byKey(_rule), findsNothing);
  });

  testWidgets('refreshing is announced with the platform label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final pending = Completer<void>();
    await tester.pumpWidget(_list(onRefresh: () => pending.future));

    final gesture = await _pull(tester, 250);
    await gesture.up();
    await tester.pump();
    await tester.pump(NoWaveMotion.normal);

    const label = DefaultMaterialLocalizations();
    final live = find.bySemanticsLabel(label.refreshIndicatorSemanticLabel);
    expect(live, findsOneWidget);
    expect(
      tester.getSemantics(live).getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );

    pending.complete();
    await tester.pumpAndSettle();
    expect(live, findsNothing);
    handle.dispose();
  });

  testWidgets('with less motion the rule holds still while refreshing', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      _list(onRefresh: () => pending.future, disableAnimations: true),
    );

    final gesture = await _pull(tester, 250);
    await gesture.up();
    await tester.pump();
    await tester.pump(NoWaveMotion.normal);

    expect(find.byKey(_segment), findsNothing);
    expect(tester.getSize(find.byKey(_rule)).width, 800);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_rule), findsNothing);
  });
}
