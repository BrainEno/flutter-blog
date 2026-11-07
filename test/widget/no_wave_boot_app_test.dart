import 'dart:async';

import 'package:belog/boot/no_wave_boot_app.dart';
import 'package:belog/boot/no_wave_splash_screen.dart';
import 'package:belog/boot/startup_failure_app.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app stand-in: the real one reads `serviceLocator`, which a unit test
/// must not build, and none of these assertions are about the router. It is a
/// full `MaterialApp` because that is what the real root is - the curtain and
/// the app each own their localizations, and neither inherits the other's.
Widget _stubApp() => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: const Scaffold(body: Text('app')),
);

void main() {
  setUp(NoWaveSplashScreen.resetForTest);

  testWidgets('the curtain is up before boot reports, and the app is not', (
    tester,
  ) async {
    final boot = Completer<void>();
    await tester.pumpWidget(
      NoWaveBootApp(boot: () => boot.future, appBuilder: _stubApp),
    );
    await tester.pump();

    expect(find.byType(NoWaveSplashScreen), findsOneWidget);
    expect(
      find.text('app'),
      findsNothing,
      reason: 'the app is only built once the injector is ready',
    );

    boot.complete();
    await tester.pump();
    await tester.pump();

    expect(
      find.text('app'),
      findsOneWidget,
      reason: 'it is built behind the curtain, so lifting it reveals content',
    );
    final overApp = find.ancestor(
      of: find.text('app'),
      matching: find.byType(IgnorePointer),
    );
    expect(
      tester.widget<IgnorePointer>(overApp.first).ignoring,
      isTrue,
      reason: 'a tap during the curtain must not reach the app',
    );

    await tester.pumpAndSettle();

    expect(find.byType(NoWaveSplashScreen), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('a boot failure replaces the curtain at once', (tester) async {
    await tester.pumpWidget(
      NoWaveBootApp(
        boot: () async => throw StateError('API_BASE_URL is missing'),
        appBuilder: _stubApp,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(StartupFailureApp), findsOneWidget);
    expect(find.byType(NoWaveSplashScreen), findsNothing);
    expect(
      find.textContaining('API_BASE_URL is missing'),
      findsOneWidget,
      reason: 'the reason is the whole point of this screen',
    );
  });

  testWidgets('the failure screen is paper on ink, never a Material seed', (
    tester,
  ) async {
    await tester.pumpWidget(
      NoWaveBootApp(
        boot: () async => throw StateError('unreadable storage'),
        appBuilder: _stubApp,
      ),
    );
    await tester.pump();
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppPalette.ink);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final scheme = app.theme!.colorScheme;
    expect(scheme.surface, AppPalette.ink);
    expect(scheme.onSurface, AppPalette.paper);
    expect(
      scheme.primary,
      AppPalette.orange,
      reason: 'the old purple seed is what this screen is being rescued from',
    );
  });
}
