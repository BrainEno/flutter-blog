import 'package:belog/core/design/components/no_wave_entrance.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list({
  Object? generation,
  int count = 10,
  bool disableAnimations = false,
  GlobalKey<NoWaveEntranceScopeState>? scopeKey,
}) {
  return MaterialApp(
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: inner!,
    ),
    home: Scaffold(
      body: NoWaveEntranceScope(
        key: scopeKey,
        generation: generation,
        child: ListView(
          children: [
            for (var i = 0; i < count; i++)
              NoWaveEntrance(
                index: i,
                child: SizedBox(height: 40, child: Text('item $i')),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The entrance opacity wrapped around item [i], or null when it does not
/// animate.
double? _opacity(WidgetTester tester, int i) => _opacityOf(tester, 'item $i');

void main() {
  group('scope', () {
    testWidgets('only the first screen claims an entrance, once each', (
      tester,
    ) async {
      final key = GlobalKey<NoWaveEntranceScopeState>();
      await tester.pumpWidget(_list(count: 0, scopeKey: key));
      final scope = key.currentState!;

      expect(scope.claim(0), Duration.zero);
      expect(scope.claim(0), isNull);
      expect(scope.claim(2), NoWaveMotion.stagger * 2);
      expect(scope.claim(NoWaveMotion.entranceCount), isNull);
      expect(scope.claim(-1), isNull);
    });

    testWidgets('a new generation enters again', (tester) async {
      final key = GlobalKey<NoWaveEntranceScopeState>();
      await tester.pumpWidget(_list(count: 0, scopeKey: key, generation: 'a'));
      expect(key.currentState!.claim(1), isNotNull);

      await tester.pumpWidget(_list(count: 0, scopeKey: key, generation: 'a'));
      expect(key.currentState!.claim(1), isNull);

      await tester.pumpWidget(_list(count: 0, scopeKey: key, generation: 'b'));
      expect(key.currentState!.claim(1), isNotNull);
    });
  });

  testWidgets('items rise in order and then hold still', (tester) async {
    await tester.pumpWidget(_list());

    // First frame: nothing has entered yet, and the second waits longer.
    expect(_opacity(tester, 0), 0);
    expect(_opacity(tester, 1), 0);

    await tester.pump(NoWaveMotion.slow ~/ 2);
    final first = _opacity(tester, 0)!;
    final second = _opacity(tester, 1)!;
    expect(first, greaterThan(0));
    expect(second, lessThan(first));

    await tester.pumpAndSettle();
    expect(_opacity(tester, 0), 1);
    expect(_opacity(tester, NoWaveMotion.entranceCount - 1), 1);
  });

  testWidgets('items past the first screen appear without waiting', (
    tester,
  ) async {
    await tester.pumpWidget(_list());

    expect(_opacity(tester, NoWaveMotion.entranceCount), isNull);
  });

  testWidgets('a rebuild does not replay the entrance', (tester) async {
    await tester.pumpWidget(_list(generation: 'feed'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_list(generation: 'feed'));
    await tester.pump();
    expect(_opacity(tester, 0), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with less motion nothing moves', (tester) async {
    await tester.pumpWidget(_list(disableAnimations: true));

    expect(_opacity(tester, 0), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('an entering item is already readable and tappable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_list());

    expect(find.bySemanticsLabel('item 0'), findsOneWidget);
    await tester.tap(find.text('item 0'), warnIfMissed: true);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('outside a scope the child is returned as is', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NoWaveEntrance(index: 0, child: Text('alone'))),
    );

    expect(_opacityOf(tester, 'alone'), isNull);
  });
}

double? _opacityOf(WidgetTester tester, String text) {
  // Only an Opacity the entrance itself added counts; the app around it may
  // have its own.
  final finder = find.descendant(
    of: find.ancestor(
      of: find.text(text),
      matching: find.byType(NoWaveEntrance),
    ),
    matching: find.byType(Opacity),
  );
  return finder.evaluate().isEmpty
      ? null
      : tester.widget<Opacity>(finder.first).opacity;
}
