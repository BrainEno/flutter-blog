import 'package:belog/core/design/components/no_wave_fade_transition.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) {
  return MaterialApp(
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: inner!,
    ),
    home: Scaffold(body: child),
  );
}

/// The fade this widget owns. MaterialApp animates the route with a
/// `FadeTransition` of its own, so match on the child rather than the type.
final _fade = find.byWidgetPredicate(
  (widget) => widget is FadeTransition && widget.child is Text,
);

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(_fade).opacity.value;

/// The policy as one of these contexts sees it.
Future<({bool reduces, Duration resolved})> _policy(
  WidgetTester tester, {
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  var reduces = false;
  var resolved = NoWaveMotion.normal;
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) {
          reduces = NoWaveMotionPolicy.reducesMotion(context);
          resolved = NoWaveMotionPolicy.resolve(context, NoWaveMotion.normal);
          return const SizedBox.shrink();
        },
      ),
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
    ),
  );
  return (reduces: reduces, resolved: resolved);
}

void main() {
  group('NoWaveMotionPolicy', () {
    testWidgets('a plain context keeps the token', (tester) async {
      final policy = await _policy(tester);

      expect(policy.reduces, isFalse);
      expect(policy.resolved, NoWaveMotion.normal);
    });

    testWidgets('the OS animation switch resolves to zero', (tester) async {
      final policy = await _policy(tester, disableAnimations: true);

      expect(policy.reduces, isTrue);
      expect(policy.resolved, Duration.zero);
    });

    testWidgets('a screen reader counts as less motion', (tester) async {
      // TalkBack and VoiceOver explore one element at a time; a page moving
      // underneath takes the reader's place away.
      final policy = await _policy(tester, accessibleNavigation: true);

      expect(policy.reduces, isTrue);
      expect(policy.resolved, Duration.zero);
    });
  });

  group('NoWaveFadeTransition', () {
    testWidgets('the first build is already opaque', (tester) async {
      await tester.pumpWidget(
        _app(const NoWaveFadeTransition(index: 0, child: Text('one'))),
      );

      expect(_fade, findsOneWidget);
      expect(_opacity(tester), 1);
    });

    testWidgets('a tab change fades the incoming stack in', (tester) async {
      await tester.pumpWidget(
        _app(const NoWaveFadeTransition(index: 0, child: Text('one'))),
      );
      await tester.pumpWidget(
        _app(const NoWaveFadeTransition(index: 1, child: Text('two'))),
      );

      expect(_opacity(tester), 0);
      await tester.pump(NoWaveMotion.normal ~/ 2);
      expect(_opacity(tester), greaterThan(0));
      expect(_opacity(tester), lessThan(1));

      await tester.pumpAndSettle();
      expect(_opacity(tester), 1);
      expect(find.text('two'), findsOneWidget);
    });

    testWidgets('rebuilding with the same index does not restart it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const NoWaveFadeTransition(index: 0, child: Text('one'))),
      );
      await tester.pumpWidget(
        _app(const NoWaveFadeTransition(index: 0, child: Text('one'))),
      );

      expect(_opacity(tester), 1);
    });

    testWidgets('less motion means no transition at all', (tester) async {
      await tester.pumpWidget(
        _app(
          const NoWaveFadeTransition(index: 0, child: Text('one')),
          disableAnimations: true,
        ),
      );

      expect(_fade, findsNothing);
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('a screen reader gets no transition either', (tester) async {
      await tester.pumpWidget(
        _app(
          const NoWaveFadeTransition(index: 0, child: Text('one')),
          accessibleNavigation: true,
        ),
      );

      expect(_fade, findsNothing);
      expect(find.text('one'), findsOneWidget);
    });
  });
}
