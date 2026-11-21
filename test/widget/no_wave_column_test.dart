import 'package:belog/core/design/components/no_wave_column.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: NoWaveSpacing.page),
          children: [child],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a short heading starts on the column edge, not in its middle', (
    tester,
  ) async {
    // The old helper let a start-aligned Column shrink to its widest line
    // and then centred it.
    await _pump(
      tester,
      1000,
      const NoWaveColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('A longer line above'), Text('Short')],
        ),
      ),
    );

    final left = (1000 - NoWaveSizes.contentColumn) / 2;
    expect(tester.getTopLeft(find.text('Short')).dx, closeTo(left, 0.5));
    expect(
      tester.getTopLeft(find.text('A longer line above')).dx,
      closeTo(left, 0.5),
    );
    expect(
      tester.getSize(find.byType(Column)).width,
      NoWaveSizes.contentColumn,
    );
  });

  testWidgets('on a phone the column is the gutter-to-gutter width', (
    tester,
  ) async {
    await _pump(tester, 390, const NoWaveColumn(child: Text('Short')));
    expect(
      tester.getTopLeft(find.text('Short')).dx,
      closeTo(NoWaveSpacing.page, 0.5),
    );
  });

  test('inset: the gutter on a phone, the column margin when wide', () {
    expect(NoWaveColumn.inset(390), NoWaveSpacing.page);
    expect(NoWaveColumn.inset(NoWaveSizes.contentColumn), NoWaveSpacing.page);
    expect(NoWaveColumn.inset(1200), (1200 - NoWaveSizes.contentColumn) / 2);
    // It always matches where a padded list's column starts.
    for (final width in [360.0, 700.0, 728.0, 800.0, 1440.0]) {
      final column = (width - 2 * NoWaveSpacing.page).clamp(
        0.0,
        NoWaveSizes.contentColumn,
      );
      final start =
          NoWaveSpacing.page + (width - 2 * NoWaveSpacing.page - column) / 2;
      expect(NoWaveColumn.inset(width), closeTo(start, 0.01), reason: '$width');
    }
  });
}
