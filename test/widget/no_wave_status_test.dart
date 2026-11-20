import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
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

TextStyle _style(WidgetTester tester, String message) =>
    tester.widget<Text>(find.text(message)).style!;

FadeTransition _fadeOver(WidgetTester tester, Finder finder) =>
    tester.widget<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)).first,
    );

void main() {
  final scheme = AppTheme.lightThemeMode.colorScheme;

  testWidgets('nothing to do: a quiet sentence and no button', (tester) async {
    await _pump(tester, const NoWaveStatus(message: 'Nothing here yet'));
    await tester.pumpAndSettle();

    final style = _style(tester, 'Nothing here yet');
    expect(style.fontFamily, 'InstrumentSerif');
    expect(style.fontSize, NoWaveTypeScale.sectionTitle);
    expect(style.color, scheme.onSurfaceVariant);
    expect(find.byType(NoWaveButton), findsNothing);
    // No ornament: just the words.
    expect(
      find.descendant(
        of: find.byType(NoWaveStatus),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
  });

  testWidgets('an action: the sentence in ink and a bordered button', (
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

    expect(_style(tester, 'Could not load').color, scheme.onSurface);
    final button = tester.widget<NoWaveButton>(find.byType(NoWaveButton));
    expect(button.variant, NoWaveButtonVariant.secondary);
    await tester.tap(find.text('Retry'));
    expect(taps, 1);
  });

  testWidgets('a long sentence keeps a short measure', (tester) async {
    await _pump(
      tester,
      const SizedBox(
        width: 600,
        child: NoWaveStatus(
          message:
              'There are no cached articles in this language on this device; '
              'connect and try again.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.getRect(find.byType(Text));
    expect(text.width, lessThanOrEqualTo(NoWaveSizes.statusMeasure));
    expect(text.center.dx, closeTo(400, 1));
  });

  testWidgets('it arrives: the words rise in, the button just behind', (
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

    final words = find.text('Could not load');
    final button = find.byType(NoWaveButton);
    expect(_fadeOver(tester, words).opacity.value, 0);
    // Read from the first frame, before the fade.
    expect(find.bySemanticsLabel(RegExp('Could not load')), findsWidgets);

    await tester.pump(NoWaveMotion.slow * NoWaveMotion.strokeLag);
    expect(_fadeOver(tester, words).opacity.value, greaterThan(0));
    expect(_fadeOver(tester, button).opacity.value, 0);

    await tester.pumpAndSettle();
    expect(_fadeOver(tester, words).opacity.value, 1);
    expect(_fadeOver(tester, button).opacity.value, 1);
    handle.dispose();
  });

  testWidgets('with less motion it is simply there', (tester) async {
    await _pump(
      tester,
      const NoWaveStatus(message: 'Nothing here yet'),
      disableAnimations: true,
    );

    expect(tester.hasRunningAnimations, isFalse);
    // (The route's own transition fades sit above the status; look inside.)
    expect(
      find.descendant(
        of: find.byType(NoWaveStatus),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('the state is announced', (tester) async {
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
    handle.dispose();
  });
}
