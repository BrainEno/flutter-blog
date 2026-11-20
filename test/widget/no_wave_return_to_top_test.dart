import 'package:belog/core/design/components/no_wave_return_to_top.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _scope = GlobalKey<NoWaveReturnToTopState>();
final _navigator = GlobalKey<NavigatorState>();

Widget _app({
  required ScrollController controller,
  int section = 0,
  bool disableAnimations = false,
  ScrollController? sideways,
}) => MaterialApp(
  navigatorKey: _navigator,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: NoWaveReturnToTop(key: _scope, section: section, child: child!),
  ),
  home: Scaffold(
    body: Column(
      children: [
        if (sideways != null)
          SizedBox(
            height: 40,
            child: ListView(
              controller: sideways,
              scrollDirection: Axis.horizontal,
              children: const [SizedBox(width: 3000)],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 400,
            itemBuilder: (context, index) => Text('row $index'),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  test('far down, the travelling part starts one screen from the top', () {
    expect(
      NoWaveReturnToTop.travelFrom(pixels: 300, top: 0, viewport: 600),
      300,
    );
    expect(
      NoWaveReturnToTop.travelFrom(pixels: 9000, top: 0, viewport: 600),
      600,
    );
  });

  testWidgets('nothing scrolled, nothing to do', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller: controller));
    expect(_scope.currentState!.toTop(), isFalse);
  });

  testWidgets('from far down: a jump close to the top, then a short travel', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller: controller));
    controller.jumpTo(9000);
    await tester.pump();

    expect(_scope.currentState!.toTop(), isTrue);
    final viewport = controller.position.viewportDimension;
    expect(controller.offset, lessThanOrEqualTo(viewport));
    expect(controller.offset, greaterThan(0), reason: 'still travelling');

    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(_scope.currentState!.toTop(), isFalse, reason: 'already there');
  });

  testWidgets('with less motion it jumps straight to the top', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(controller: controller, disableAnimations: true),
    );
    controller.jumpTo(9000);
    await tester.pump();

    expect(_scope.currentState!.toTop(), isTrue);
    expect(controller.offset, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a list under another page is left where it is', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller: controller));
    controller.jumpTo(2000);
    await tester.pump();

    _navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();

    expect(_scope.currentState!.toTop(), isFalse);
    expect(controller.offset, 2000);
  });

  testWidgets('a sideways scroll is not the list it returns', (tester) async {
    final controller = ScrollController();
    final sideways = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(sideways.dispose);
    await tester.pumpWidget(_app(controller: controller, sideways: sideways));
    sideways.jumpTo(500);
    await tester.pump();

    expect(_scope.currentState!.toTop(), isFalse);
    expect(sideways.offset, 500);
  });

  testWidgets('each section returns only its own list', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller: controller));
    controller.jumpTo(2000);
    await tester.pump();

    // Another section is on screen now; the list scrolled in section 0 stays.
    await tester.pumpWidget(_app(controller: controller, section: 1));
    expect(_scope.currentState!.toTop(), isFalse);
    expect(controller.offset, 2000);

    await tester.pumpWidget(_app(controller: controller));
    expect(_scope.currentState!.toTop(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });
}
