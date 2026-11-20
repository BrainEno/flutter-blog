import 'package:belog/core/design/components/no_wave_sliding_tabs.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _labels = ['Latest', 'Featured', 'Popular', 'Following'];

Widget _tabs({
  required int selected,
  ValueChanged<int>? onSelected,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
  double textScale = 1,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: NoWaveSlidingTabs(
            labels: _labels,
            selected: selected,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    ),
  ),
);

Finder _word(String label) => find.descendant(
  of: find.widgetWithText(NoWaveSlidingTab, label),
  matching: find.text(label),
);

Rect _rule(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('no-wave-sliding-rule')));

void main() {
  group('ruleAt', () {
    const from = (0.0, 40.0);
    const to = (100.0, 160.0);

    test('starts where it was and ends where it goes', () {
      expect(NoWaveSlidingTabs.ruleAt(from, to, 0), from);
      expect(NoWaveSlidingTabs.ruleAt(from, to, 1), to);
    });

    test('the edge on the side of travel leads, so the rule stretches', () {
      final (start, end) = NoWaveSlidingTabs.ruleAt(from, to, 0.5);
      final startShare = (start - from.$1) / (to.$1 - from.$1);
      final endShare = (end - from.$2) / (to.$2 - from.$2);
      expect(endShare, greaterThan(startShare));
      expect(end - start, greaterThan(to.$2 - to.$1));

      // Going back, the start edge leads instead.
      final (backStart, backEnd) = NoWaveSlidingTabs.ruleAt(to, from, 0.5);
      final backStartShare = (to.$1 - backStart) / (to.$1 - from.$1);
      final backEndShare = (to.$2 - backEnd) / (to.$2 - from.$2);
      expect(backStartShare, greaterThan(backEndShare));
    });

    test('the trailing edge waits strokeLag before moving', () {
      final (start, _) = NoWaveSlidingTabs.ruleAt(
        from,
        to,
        NoWaveMotion.strokeLag,
      );
      expect(start, from.$1);
    });
  });

  testWidgets('the rule sits under the chosen word, as wide as it', (
    tester,
  ) async {
    await tester.pumpWidget(_tabs(selected: 1));
    final word = tester.getRect(_word('Featured'));
    final rule = _rule(tester);

    expect(rule.height, NoWaveSizes.accentRule);
    expect(rule.center.dx, closeTo(word.center.dx, 1));
    // Measured at the selected weight, so it covers the drawn word.
    expect(rule.width, greaterThanOrEqualTo(word.width - 1));
    expect(rule.top, greaterThan(word.bottom));
  });

  testWidgets('words are set from the start, and the rule starts with them', (
    tester,
  ) async {
    await tester.pumpWidget(_tabs(selected: 2));
    final word = tester.getRect(_word('Popular'));
    expect(_rule(tester).left, closeTo(word.left, 1));
    // The default inset lines the first word up with the page margin.
    expect(
      tester.getRect(_word('Latest')).left,
      closeTo(
        tester.getRect(find.byType(NoWaveSlidingTabs)).left +
            NoWaveSpacing.page,
        1,
      ),
    );
  });

  testWidgets('inside a padded column the first word sits flush', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(NoWaveSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Heading'),
                NoWaveSlidingTabs(
                  inset: 0,
                  labels: _labels,
                  selected: 0,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final heading = tester.getRect(find.text('Heading'));
    expect(tester.getRect(_word('Latest')).left, closeTo(heading.left, 1));
    expect(_rule(tester).left, closeTo(heading.left, 1));
  });

  testWidgets('a tap reports the word; the caller decides', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(_tabs(selected: 0, onSelected: taps.add));

    await tester.tap(find.widgetWithText(NoWaveSlidingTab, 'Popular'));
    await tester.pumpAndSettle();

    expect(taps, [2]);
    // Nothing moved on its own: the caller did not change the selection.
    expect(
      _rule(tester).center.dx,
      closeTo(tester.getRect(_word('Latest')).center.dx, 1),
    );
  });

  testWidgets('choosing another word draws the rule across like a stroke', (
    tester,
  ) async {
    await tester.pumpWidget(_tabs(selected: 0));
    final first = _rule(tester);
    final target = tester.getRect(_word('Popular'));

    await tester.pumpWidget(_tabs(selected: 2));
    await tester.pump(NoWaveMotion.slow ~/ 2);
    final middle = _rule(tester);
    expect(middle.left, greaterThan(first.left));
    expect(middle.right, lessThan(target.right + 1));
    expect(
      middle.width,
      greaterThan(first.width),
      reason: 'the leading edge is ahead of the trailing one',
    );

    await tester.pumpAndSettle();
    expect(_rule(tester).center.dx, closeTo(target.center.dx, 1));
  });

  testWidgets('a move interrupted mid-way continues from where it is', (
    tester,
  ) async {
    await tester.pumpWidget(_tabs(selected: 0));
    await tester.pumpWidget(_tabs(selected: 3));
    await tester.pump(NoWaveMotion.slow ~/ 2);
    final interrupted = _rule(tester);

    await tester.pumpWidget(_tabs(selected: 1));
    await tester.pump();
    expect(_rule(tester).left, closeTo(interrupted.left, 2));

    await tester.pumpAndSettle();
    expect(
      _rule(tester).center.dx,
      closeTo(tester.getRect(_word('Featured')).center.dx, 1),
    );
  });

  testWidgets('with less motion the rule is placed, not moved', (tester) async {
    await tester.pumpWidget(_tabs(selected: 0, disableAnimations: true));
    await tester.pumpWidget(_tabs(selected: 3, disableAnimations: true));
    await tester.pump();

    expect(
      _rule(tester).center.dx,
      closeTo(tester.getRect(_word('Following')).center.dx, 1),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('right-to-left starts at the right', (tester) async {
    await tester.pumpWidget(_tabs(selected: 0, direction: TextDirection.rtl));
    final latest = tester.getRect(_word('Latest'));
    final following = tester.getRect(_word('Following'));

    expect(latest.left, greaterThan(following.left));
    expect(_rule(tester).center.dx, closeTo(latest.center.dx, 1));
  });

  testWidgets('each word is a button of one group; the rule is not read', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_tabs(selected: 1));

    for (final (label, chosen) in [('Featured', true), ('Latest', false)]) {
      final tab = find.widgetWithText(NoWaveSlidingTab, label);
      final data = tester.getSemantics(tab).getSemanticsData();
      expect(data.label, label, reason: 'the word is read once, as is');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: tab,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.button == true,
              ),
            )
            .first,
      );
      expect(semantics.properties.selected, chosen);
    }
    handle.dispose();
  });

  testWidgets('every word is at least a tap target tall', (tester) async {
    await tester.pumpWidget(_tabs(selected: 0));
    for (final label in _labels) {
      expect(
        tester.getSize(find.widgetWithText(NoWaveSlidingTab, label)).height,
        greaterThanOrEqualTo(NoWaveSizes.tapTarget),
      );
    }
  });

  for (final (name, theme) in [
    ('light', AppTheme.lightThemeMode),
    ('dark', AppTheme.darkThemeMode),
  ]) {
    testWidgets('$name: 2x text on 320dp scrolls instead of overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: NoWaveSlidingTabs(
                labels: _labels,
                selected: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_word('Following')).right, greaterThan(320));

      // Choosing the last word brings it on screen.
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: NoWaveSlidingTabs(
                labels: _labels,
                selected: 3,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final last = tester.getRect(_word('Following'));
      expect(last.right, lessThanOrEqualTo(320));
      expect(last.left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  }
}
