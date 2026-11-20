import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rule = ValueKey('no-wave-snackbar-rule');

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
  testWidgets('a snackbar carries an orange rule down its start edge', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    final message = find.text(
      'Saved to your library. It will stay available offline.',
    );
    expect(message, findsOneWidget);
    expect(find.byType(NoWaveSnackBarContent), findsOneWidget);

    final rule = tester.getRect(find.byKey(_rule));
    final text = tester.getRect(message);
    expect(rule.width, NoWaveSizes.accentRule);
    expect(rule.right, lessThan(text.left));
    // As tall as the message, so a wrapped message is marked as one.
    expect(rule.top, closeTo(text.top, 1));
    expect(rule.bottom, closeTo(text.bottom, 1));
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(_rule),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      AppPalette.orange,
    );
    // The action is still Material's own.
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
  });

  testWidgets('at 2x the rule follows the message onto its second line', (
    tester,
  ) async {
    await tester.pumpWidget(_app(textScale: 2));
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final text = tester.getRect(
      find.text('Saved to your library. It will stay available offline.'),
    );
    final rule = tester.getRect(find.byKey(_rule));
    expect(rule.height, closeTo(text.height, 1));
    expect(rule.height, greaterThan(28 * 2), reason: 'wrapped onto 2+ lines');
  });
}
