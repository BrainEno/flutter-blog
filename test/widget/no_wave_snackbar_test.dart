import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({double textScale = 1}) => MaterialApp(
  theme: AppTheme.lightThemeMode,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 640),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showSnackBar(
              context,
              'Saved to your library. It will stay available offline.',
              action: SnackBarAction(label: 'Undo', onPressed: () {}),
            ),
            child: const Text('Go'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  const sentence = 'Saved to your library. It will stay available offline.';

  testWidgets('a snackbar is the sentence alone, with no rule in front', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text(sentence), findsOneWidget);
    expect(find.byType(NoWaveSnackBarContent), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NoWaveSnackBarContent),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    // The words start where the bar's own padding puts them.
    final bar = tester.getRect(find.byType(SnackBar));
    final text = tester.getRect(find.text(sentence));
    expect(text.left - bar.left, lessThanOrEqualTo(NoWaveSpacing.large));
    // The action is still Material's own.
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
  });

  testWidgets('at 2x the message wraps instead of clipping', (tester) async {
    await tester.pumpWidget(_app(textScale: 2));
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final text = tester.getRect(find.text(sentence));
    expect(text.height, greaterThan(28 * 2), reason: 'wrapped onto 2+ lines');
  });
}
