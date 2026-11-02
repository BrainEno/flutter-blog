import 'package:belog/core/startup/startup_failure_app.dart';
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
