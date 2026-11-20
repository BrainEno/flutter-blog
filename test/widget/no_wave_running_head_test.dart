import 'package:belog/core/design/components/no_wave_running_head.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({
  required bool visible,
  VoidCallback? onTap,
  bool disableAnimations = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(
      appBar: AppBar(
        title: NoWaveRunningHead(
          title: 'A long walk',
          visible: visible,
          semanticLabel: 'A long walk, back to top',
          onTap: onTap,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('hidden, it is not built: the page carries the title once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_bar(visible: false));
    expect(find.text('A long walk'), findsNothing);
    expect(find.bySemanticsLabel('A long walk, back to top'), findsNothing);
    handle.dispose();
  });

  testWidgets('it rises into the bar, and a tap goes back to the top', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(_bar(visible: false, onTap: () => taps++));
    await tester.pumpWidget(_bar(visible: true, onTap: () => taps++));

    // Half way in: below its place and still fading.
    await tester.pump(NoWaveMotion.normal ~/ 2);
    final rising = tester.getRect(find.text('A long walk'));
    await tester.pumpAndSettle();
    final settled = tester.getRect(find.text('A long walk'));
    expect(rising.top, greaterThan(settled.top));

    final head = find.bySemanticsLabel('A long walk, back to top');
    expect(head, findsOneWidget);
    final data = tester.getSemantics(head).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('no-wave-running-head'))).height,
      greaterThanOrEqualTo(NoWaveSizes.tapTarget),
    );

    await tester.tap(find.text('A long walk'));
    expect(taps, 1);

    await tester.pumpWidget(_bar(visible: false, onTap: () => taps++));
    await tester.pumpAndSettle();
    expect(find.text('A long walk'), findsNothing);
    handle.dispose();
  });

  testWidgets('with less motion it appears in place', (tester) async {
    await tester.pumpWidget(_bar(visible: false, disableAnimations: true));
    await tester.pumpWidget(_bar(visible: true, disableAnimations: true));
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.text('A long walk'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('passed: only once the title is wholly under the bar', (
    tester,
  ) async {
    final title = GlobalKey();
    bool? passed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(),
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              passed = NoWaveRunningHead.passed(
                title.currentContext,
                notification,
              );
              return false;
            },
            child: ListView(
              children: [
                const SizedBox(height: 100),
                SizedBox(key: title, height: 40, child: const Text('Title')),
                const SizedBox(height: 3000),
              ],
            ),
          ),
        ),
      ),
    );
    final list = find.byType(ListView);

    await tester.drag(list, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(passed, isFalse, reason: 'the bottom 20pt is still showing');

    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(passed, isTrue);

    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(passed, isFalse);
  });

  testWidgets('toTop travels back, or jumps with less motion', (tester) async {
    for (final still in [false, true]) {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () =>
                          NoWaveRunningHead.toTop(context, controller),
                      child: const Text('top'),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        children: const [SizedBox(height: 4000)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(1500);
      await tester.pump();
      await tester.tap(find.text('top'));
      await tester.pump();
      if (still) {
        expect(controller.offset, 0);
      } else {
        expect(controller.offset, greaterThan(0));
        await tester.pumpAndSettle();
        expect(controller.offset, 0);
      }
    }
  });
}
