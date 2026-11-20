import 'package:belog/features/blog/presentation/editor/structured_local_page_chrome.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _zh = lookupAppLocalizations(const Locale('zh'));

/// A session close that answers from a script and records how it was asked.
class _Close {
  _Close(this.answers);

  final List<bool> answers;
  final calls = <bool>[];

  Future<bool> call({bool abandonUnsaved = false}) async {
    calls.add(abandonUnsaved);
    return answers[calls.length - 1];
  }
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// A page that leaves through [closeStructuredSessionForExit] and records
/// what it was told.
class _Leaver extends StatefulWidget {
  const _Leaver({required this.close, required this.results});

  final _Close close;
  final List<bool> results;

  @override
  State<_Leaver> createState() => _LeaverState();
}

class _LeaverState extends State<_Leaver> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          widget.results.add(
            await closeStructuredSessionForExit(context, widget.close.call),
          );
        },
        child: const Text('leave'),
      ),
    ),
  );
}

void main() {
  group('StructuredLocalScaffold', () {
    testWidgets('the back arrow and the system back both run onLeave', (
      tester,
    ) async {
      var leaves = 0;
      await tester.pumpWidget(
        _app(
          StructuredLocalScaffold(
            title: 'Local edit',
            onLeave: () async => leaves++,
            actions: const [Icon(Icons.history)],
            body: const Text('body'),
          ),
        ),
      );

      expect(find.text('Local edit'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.text('body'), findsOneWidget);

      await tester.tap(find.byTooltip(_zh.actionBack));
      await tester.pump();
      expect(leaves, 1);

      // The route cannot pop on its own: the page decides after closing.
      final popped = await tester.binding.handlePopRoute();
      await tester.pump();
      expect(popped, isTrue);
      expect(leaves, 2);
      expect(find.text('body'), findsOneWidget);
    });
  });

  group('closeStructuredSessionForExit', () {
    testWidgets('a clean close pops without asking', (tester) async {
      final close = _Close([true]);
      final results = <bool>[];
      await tester.pumpWidget(_app(_Leaver(close: close, results: results)));

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.text(_zh.structuredExitTitle), findsNothing);
      expect(close.calls, [false]);
      expect(results, [true]);
    });

    testWidgets('an unsaved write asks, and cancelling keeps editing', (
      tester,
    ) async {
      final close = _Close([false]);
      final results = <bool>[];
      await tester.pumpWidget(_app(_Leaver(close: close, results: results)));

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      expect(find.text(_zh.structuredExitTitle), findsOneWidget);
      expect(find.text(_zh.structuredExitBody), findsOneWidget);

      await tester.tap(find.text(_zh.actionCancel));
      await tester.pumpAndSettle();

      expect(close.calls, [false], reason: 'nothing was abandoned');
      expect(results, [false]);
    });

    testWidgets('confirming abandons the unsaved write, then pops', (
      tester,
    ) async {
      final close = _Close([false, true]);
      final results = <bool>[];
      await tester.pumpWidget(_app(_Leaver(close: close, results: results)));

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_zh.structuredExitAction));
      await tester.pumpAndSettle();

      expect(close.calls, [false, true]);
      expect(results, [true]);
    });

    testWidgets('a refused abandon keeps the page', (tester) async {
      final close = _Close([false, false]);
      final results = <bool>[];
      await tester.pumpWidget(_app(_Leaver(close: close, results: results)));

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_zh.structuredExitAction));
      await tester.pumpAndSettle();

      expect(close.calls, [false, true]);
      expect(results, [false]);
    });
  });

  group('StructuredLocalNotice', () {
    testWidgets('only the live notice is a live region', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              Expanded(child: StructuredLocalNotice('loading', live: true)),
              Expanded(child: StructuredLocalNotice('changed')),
            ],
          ),
        ),
      );

      Finder liveAbove(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      );
      expect(liveAbove('loading'), findsOneWidget);
      expect(liveAbove('changed'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
