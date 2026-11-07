import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_wordmark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/boot/no_wave_splash_screen.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounts the curtain the way `NoWaveBootApp` does: inside a localized app
/// whose media query can be narrowed and whose motion can be switched off.
Future<void> _pumpCurtain(
  WidgetTester tester, {
  required Future<void> ready,
  required VoidCallback onFinished,
  Locale locale = const Locale('zh'),
  double textScale = 1,
  bool disableAnimations = false,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: NoWaveSplashScreen(ready: ready, onFinished: onFinished),
    ),
  );
}

void main() {
  setUp(NoWaveSplashScreen.resetForTest);

  testWidgets('the first frame is the curtain, not a spinner', (tester) async {
    final ready = Completer<void>();
    var finished = 0;

    await _pumpCurtain(
      tester,
      ready: ready.future,
      onFinished: () => finished++,
    );

    expect(find.text('000'), findsOneWidget);
    expect(find.text('载入中 · LOADING'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NoWaveSplashScreen),
        matching: find.byType(FractionalTranslation),
      ),
      findsNWidgets(NoWaveSizes.splashColumns),
      reason: 'six columns, the same count the web loader cuts',
    );
    expect(find.byType(NoWaveWordmark), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'no-wave replaces spinners with words',
    );
    expect(finished, 0);

    ready.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the counter climbs, reaches 100 and then reports', (
    tester,
  ) async {
    final ready = Completer<void>();
    var finished = false;

    await _pumpCurtain(
      tester,
      ready: ready.future,
      onFinished: () => finished = true,
    );
    ready.complete();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.text('000'),
      findsNothing,
      reason: 'the counter is choreography and starts immediately',
    );
    expect(finished, isFalse);

    // 088 → 100 is the last stretch, after boot reported. It is a fixed
    // number of frames away, not a guess: stepping keeps the assertion about
    // the destination instead of about the scheduler's arithmetic.
    var sawHundred = false;
    for (var frame = 0; frame < 60 && !sawHundred; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      sawHundred = tester.any(find.text('100'));
    }
    expect(sawHundred, isTrue, reason: 'the counter ends on 100, not on 088');

    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('an instant boot still gets a complete curtain', (tester) async {
    final ready = Completer<void>();
    var finished = false;

    await _pumpCurtain(
      tester,
      ready: ready.future,
      onFinished: () => finished = true,
    );
    ready.complete();
    await tester.pump();

    await tester.pump(NoWaveMotion.minimumSplash);
    expect(
      finished,
      isFalse,
      reason: 'anything shorter than the minimum reads as a flicker',
    );

    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('reduced motion shows a still frame and hands over at once', (
    tester,
  ) async {
    final ready = Completer<void>();
    var finished = false;

    await _pumpCurtain(
      tester,
      ready: ready.future,
      onFinished: () => finished = true,
      disableAnimations: true,
    );
    expect(find.text('000'), findsOneWidget);

    ready.complete();
    await tester.pump();
    await tester.pump();

    expect(
      finished,
      isTrue,
      reason: 'no counter, no curtain: the app takes over as soon as it can',
    );
    expect(
      find.text('000'),
      findsOneWidget,
      reason: 'the still frame is the first frame, not a fake 100',
    );
  });

  testWidgets('the sequence plays once per process', (tester) async {
    final firstReady = Completer<void>();
    var firstFinished = false;

    await _pumpCurtain(
      tester,
      ready: firstReady.future,
      onFinished: () => firstFinished = true,
    );
    firstReady.complete();
    await tester.pumpAndSettle();
    expect(firstFinished, isTrue);

    // Unmount first: pumping the same tree again would reuse the element and
    // its state, which would prove nothing about a second cold start.
    await tester.pumpWidget(const SizedBox.shrink());

    // A rebuild inside the same process (hot restart of the widget tree) must
    // not replay a three-second opening.
    final secondReady = Completer<void>();
    var secondFinished = false;
    await _pumpCurtain(
      tester,
      ready: secondReady.future,
      onFinished: () => secondFinished = true,
    );
    secondReady.complete();
    await tester.pump();
    await tester.pump();

    expect(secondFinished, isTrue);
  });

  testWidgets('a screen reader hears one loading announcement', (tester) async {
    final handle = tester.ensureSemantics();
    final ready = Completer<void>();

    await _pumpCurtain(tester, ready: ready.future, onFinished: () {});

    expect(find.bySemanticsLabel('No Wave 正在载入'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^00\d')),
      findsNothing,
      reason: 'the counter must not narrate every frame',
    );

    ready.complete();
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('320dp at a doubled text scale does not overflow', (
    tester,
  ) async {
    final ready = Completer<void>();

    await _pumpCurtain(
      tester,
      ready: ready.future,
      onFinished: () {},
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);

    ready.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the English curtain uses the English label', (tester) async {
    final ready = Completer<void>();

    await _pumpCurtain(
      tester,
      ready: ready.future,
      onFinished: () {},
      locale: const Locale('en'),
    );

    expect(find.text('LOADING · NO WAVE'), findsOneWidget);
    expect(find.text('No Wave · 無浪潮'), findsOneWidget);

    ready.complete();
    await tester.pumpAndSettle();
  });
}
