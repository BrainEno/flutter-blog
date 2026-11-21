import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_list_note.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightThemeMode,
      home: Scaffold(body: ListView(children: [child])),
    ),
  );
}

void main() {
  final scheme = AppTheme.lightThemeMode.colorScheme;

  testWidgets('a reason in the loading label voice and a quiet way on', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      NoWaveListNote(
        message: 'The next page did not load',
        actionLabel: 'Retry',
        onAction: () => taps++,
      ),
    );

    final style = tester
        .widget<Text>(find.text('The next page did not load'))
        .style!;
    // Same voice as "loading more", not the serif of a whole-page status.
    expect(style.fontFamily, 'InterTight');
    expect(style.color, scheme.onSurfaceVariant);

    final button = tester.widget<NoWaveButton>(find.byType(NoWaveButton));
    expect(button.variant, NoWaveButtonVariant.quiet);
    expect(
      tester.getSize(find.byType(NoWaveButton)).height,
      greaterThanOrEqualTo(NoWaveSizes.tapTarget),
    );

    await tester.tap(find.text('Retry'));
    expect(taps, 1);
  });

  testWidgets('a long reason wraps inside the status measure', (tester) async {
    await _pump(
      tester,
      NoWaveListNote(message: List.filled(40, 'word').join(' ')),
    );

    expect(find.byType(NoWaveButton), findsNothing);
    expect(
      tester.getSize(find.byType(Text)).width,
      lessThanOrEqualTo(NoWaveSizes.statusMeasure),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('only a background failure is announced', (tester) async {
    Semantics noteSemantics() => tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(NoWaveListNote),
            matching: find.byType(Semantics),
          )
          .first,
    );

    await _pump(tester, const NoWaveListNote(message: 'Only so deep'));
    expect(noteSemantics().properties.liveRegion, isNot(isTrue));

    await _pump(
      tester,
      NoWaveListNote(
        message: 'The next page did not load',
        actionLabel: 'Retry',
        onAction: () {},
        live: true,
      ),
    );
    expect(noteSemantics().properties.liveRegion, isTrue);
  });
}
