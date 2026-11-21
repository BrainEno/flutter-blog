import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_dock.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/read_aloud_fakes.dart';
import 'read_aloud_controls_test.dart' show readerFor;

Widget _dock(
  ReadAloudController reader, {
  VerticalDirection? away,
  VoidCallback? onReturn,
  double width = 360,
  double scale = 1,
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.lightThemeMode,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: SizedBox(
      width: width,
      child: ReadAloudDock(
        controller: reader,
        voiceAway: away,
        onReturn: onReturn,
      ),
    ),
  ),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));

  Future<(FakeSpeechEngine, ReadAloudController)> playing(
    WidgetTester tester,
  ) async {
    final engine = FakeSpeechEngine();
    final reader = readerFor(engine, FakeReadAloudPreferences());
    await reader.initialize();
    addTearDown(() async {
      reader.dispose();
      await flushSpeech();
      await engine.close();
    });
    reader.togglePlayback();
    // Lets the speech engine's queued calls run. A real timer
    // (`flushSpeech`) would never fire inside the test's fake clock.
    await tester.pump();
    return (engine, reader);
  }

  testWidgets('pause, resume and stop from the foot of the page', (
    tester,
  ) async {
    final (engine, reader) = await playing(tester);
    await tester.pumpWidget(_dock(reader));

    expect(find.text(l10n.readAloudListening(0)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('read-aloud-dock-play')));
    await tester.pump();
    expect(reader.phase, ReadAloudPhase.paused);
    expect(find.text(l10n.readAloudPaused(0)), findsOneWidget);
    expect(find.byTooltip(l10n.readAloudResume), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('read-aloud-dock-play')));
    await tester.pump();
    expect(reader.phase, ReadAloudPhase.playing);

    final stops = engine.stopCount;
    await tester.tap(find.byTooltip(l10n.readAloudStop));
    await tester.pump();
    await tester.pump();
    expect(reader.phase, ReadAloudPhase.idle);
    expect(engine.stopCount, greaterThan(stops));
  });

  testWidgets('the ink rule on its top edge is how far in the voice is', (
    tester,
  ) async {
    final (engine, reader) = await playing(tester);
    await tester.pumpWidget(_dock(reader));
    final progress = find.byKey(const ValueKey('read-aloud-dock-progress'));
    expect(
      tester.widget<FractionallySizedBox>(progress).widthFactor,
      reader.progress,
    );

    engine.event(engine.calls.last.id, SpeechEventType.completed);
    await tester.pump();
    expect(reader.progress, greaterThan(0));
    expect(
      tester.widget<FractionallySizedBox>(progress).widthFactor,
      reader.progress,
    );
    final dock = tester.getRect(find.byType(ReadAloudDock));
    expect(tester.getRect(progress).top, dock.top);
  });

  testWidgets('the way back appears only when the voice is out of view', (
    tester,
  ) async {
    final (_, reader) = await playing(tester);
    var returns = 0;
    await tester.pumpWidget(_dock(reader, onReturn: () => returns++));
    expect(find.byKey(const ValueKey('read-aloud-return')), findsNothing);

    await tester.pumpWidget(
      _dock(reader, away: VerticalDirection.up, onReturn: () => returns++),
    );
    expect(find.text(l10n.readAloudReturn), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.pumpWidget(
      _dock(reader, away: VerticalDirection.down, onReturn: () => returns++),
    );
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('read-aloud-return')));
    expect(returns, 1);
  });

  testWidgets('fits a narrow phone at large text', (tester) async {
    final (_, reader) = await playing(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _dock(
        reader,
        away: VerticalDirection.down,
        onReturn: () {},
        width: 320,
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
