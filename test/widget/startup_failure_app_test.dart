import 'package:belog/boot/startup_failure_app.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpFailure(WidgetTester tester, String message) {
  return tester.pumpWidget(StartupFailureApp(message: message));
}

void main() {
  testWidgets('a startup failure is shown instead of a blank window', (
    tester,
  ) async {
    await pumpFailure(
      tester,
      'API base URL not configured. Set API_BASE_URL via '
      '--dart-define-from-file=env.json',
    );

    expect(find.text('无法启动 · Unable to start'), findsOneWidget);
    expect(find.textContaining('API base URL not configured'), findsOneWidget);
    expect(find.textContaining('env.example.json'), findsOneWidget);
    expect(find.textContaining('scripts/run_android.cmd'), findsOneWidget);
  });

  testWidgets('the screen is paper on ink, not a Material seed', (
    tester,
  ) async {
    await pumpFailure(tester, 'API base URL not configured');

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppPalette.ink,
    );
    final scheme = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .colorScheme;
    expect(scheme.surface, AppPalette.ink);
    expect(scheme.onSurface, AppPalette.paper);
    expect(
      scheme.primary,
      AppPalette.orange,
      reason: 'the purple colorSchemeSeed that shipped before this screen',
    );
  });

  testWidgets('the failure text can be selected and copied', (tester) async {
    await pumpFailure(tester, 'Invalid API_BASE_URL: ""');

    final selectable = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    );
    expect(
      selectable.map((widget) => widget.data),
      contains('Invalid API_BASE_URL: ""'),
    );
  });
}
