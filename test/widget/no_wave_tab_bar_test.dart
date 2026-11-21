import 'package:belog/core/design/components/no_wave_tab_bar.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = [
  NoWaveTabDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  NoWaveTabDestination(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: 'Search',
  ),
  NoWaveTabDestination(
    icon: Icons.bookmark_border,
    selectedIcon: Icons.bookmark,
    label: 'Saved',
  ),
  NoWaveTabDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Profile',
  ),
];

class _Host extends StatefulWidget {
  const _Host({required this.taps});
  final List<int> taps;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: NoWaveTabBar(
      destinations: _destinations,
      selectedIndex: selected,
      onSelected: (index) {
        widget.taps.add(index);
        setState(() => selected = index);
      },
    ),
  );
}

Future<List<int>> _pump(
  WidgetTester tester, {
  bool disableAnimations = false,
  double textScale = 1,
  double width = 400,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final taps = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightThemeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: _Host(taps: taps),
    ),
  );
  await tester.pumpAndSettle();
  return taps;
}

Rect _rule(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('no-wave-tab-bar-rule')));

void main() {
  final scheme = AppTheme.lightThemeMode.colorScheme;

  testWidgets('the chosen slot carries the ink rule on the top edge', (
    tester,
  ) async {
    await _pump(tester);
    final bar = tester.getRect(find.byType(NoWaveTabBar));
    final rule = _rule(tester);
    final word = tester.getRect(find.text('Home'));

    expect(rule.top, closeTo(bar.top, 0.5));
    expect(rule.height, NoWaveSizes.accentRule);
    // As wide as the word (or the glyph), centred over the first slot.
    expect(rule.center.dx, closeTo(400 / 4 / 2, 1));
    expect(rule.width, greaterThanOrEqualTo(word.width - 1));
    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('no-wave-tab-bar-rule')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(box.color, scheme.onSurface);
  });

  testWidgets('the chosen glyph is filled and its word in ink', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.search_outlined), findsOneWidget);
    final chosen = tester.widget<Text>(find.text('Home'));
    final other = tester.widget<Text>(find.text('Search'));
    final chosenStyle = DefaultTextStyle.of(
      tester.element(find.text('Home')),
    ).style;
    final otherStyle = DefaultTextStyle.of(
      tester.element(find.text('Search')),
    ).style;
    expect(chosen.data, 'Home');
    expect(other.data, 'Search');
    expect(chosenStyle.color, scheme.onSurface);
    expect(otherStyle.color, scheme.onSurfaceVariant);
    expect(chosenStyle.fontSize, NoWaveTypeScale.tabLabel);
  });

  testWidgets('choosing draws the rule across, stretching on the way', (
    tester,
  ) async {
    final taps = await _pump(tester);
    final before = _rule(tester);

    await tester.tap(find.text('Saved'));
    await tester.pump();
    await tester.pump(NoWaveMotion.slow * 0.5);
    final mid = _rule(tester);
    // Mid-move the leading edge has gone ahead and the trailing edge is
    // still catching up: the rule spans more than either word.
    expect(mid.width, greaterThan(before.width * 1.5));

    await tester.pumpAndSettle();
    final after = _rule(tester);
    expect(after.center.dx, closeTo(400 / 4 * 2.5, 1));
    expect(taps, [2]);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  testWidgets('tapping the chosen slot still reports it', (tester) async {
    final taps = await _pump(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(taps, [0]);
  });

  testWidgets('with less motion the rule is placed, not drawn', (tester) async {
    await _pump(tester, disableAnimations: true);
    await tester.tap(find.text('Profile'));
    await tester.pump();
    // One frame later it is already under the new word.
    expect(_rule(tester).center.dx, closeTo(400 / 4 * 3.5, 1));
  });

  testWidgets('each slot is a selected or unselected button', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    for (final (label, chosen) in [('Home', true), ('Search', false)]) {
      final data = tester.getSemantics(find.text(label)).getSemanticsData();
      expect(data.label, label);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      final semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text(label),
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

  testWidgets('large text at 320dp still fits the bar', (tester) async {
    await _pump(tester, textScale: 3, width: 320);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(NoWaveTabBar)).height,
      NoWaveSizes.tabBar,
    );
  });
}
