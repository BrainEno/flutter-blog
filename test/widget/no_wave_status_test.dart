import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightThemeMode,
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: page!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

BoxDecoration _square(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find.descendant(
                of: find.byKey(const ValueKey('no-wave-status-mark')),
                matching: find.byType(DecoratedBox),
              ),
            )
            .decoration
        as BoxDecoration;

double _ruleScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(NoWaveStatusMark),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.storage[0];
}

void main() {
  testWidgets('nothing to do: a hollow mark and no button', (tester) async {
    await _pump(tester, const NoWaveStatus(message: 'Nothing here yet'));
    await tester.pumpAndSettle();

    final square = _square(tester);
    expect(square.color, isNull);
    expect(square.border, isNotNull);
    expect(find.byType(NoWaveButton), findsNothing);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('an action: a filled orange mark and a bordered button', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      NoWaveStatus(
        message: 'Could not load',
        actionLabel: 'Retry',
        onAction: () => taps++,
      ),
    );
    await tester.pumpAndSettle();

    expect(_square(tester).color, AppPalette.orange);
    final button = tester.widget<NoWaveButton>(find.byType(NoWaveButton));
    expect(button.variant, NoWaveButtonVariant.secondary);
    await tester.tap(find.text('Retry'));
    expect(taps, 1);
  });

  testWidgets('it arrives: lines draw out, then the words rise in', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      NoWaveStatus(
        message: 'Could not load',
        actionLabel: 'Retry',
        onAction: () {},
      ),
    );

    expect(_ruleScale(tester), 0);
    // Read and tappable from the first frame, before the fade.
    expect(find.bySemanticsLabel(RegExp('Could not load')), findsWidgets);

    await tester.pump(NoWaveMotion.slow * NoWaveMotion.strokeLag);
    expect(_ruleScale(tester), greaterThan(0));
    expect(_ruleScale(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(_ruleScale(tester), 1);
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('Could not load'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
    handle.dispose();
  });

  testWidgets('with less motion it is simply there', (tester) async {
    await _pump(
      tester,
      const NoWaveStatus(message: 'Nothing here yet'),
      disableAnimations: true,
    );

    expect(tester.hasRunningAnimations, isFalse);
    expect(
      find.descendant(
        of: find.byType(NoWaveStatusMark),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('Nothing here yet'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('the mark is not read; the state is announced', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const NoWaveStatus(message: 'Nothing here yet'));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(find.byType(NoWaveStatus))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    // The mark is drawn, not typed: there is no glyph for a reader to spell.
    expect(find.text('—'), findsNothing);
    expect(
      find.ancestor(
        of: find.byType(NoWaveStatusMark),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
    handle.dispose();
  });
}
