import 'package:belog/core/utils/search_debounce.dart';
import 'package:flutter_test/flutter_test.dart';

/// `testWidgets` runs in a fake-async zone, so `tester.pump(duration)` moves
/// the debounce timer deterministically without real waiting.
void main() {
  test('the shared delay is the 300ms every search box used before', () {
    expect(kSearchDebounceDelay, const Duration(milliseconds: 300));
    expect(SearchDebounce().delay, kSearchDebounceDelay);
  });

  testWidgets('runs the action once the delay has passed', (tester) async {
    final debounce = SearchDebounce();
    addTearDown(debounce.dispose);
    final calls = <String>[];

    debounce(() => calls.add('query'));
    expect(debounce.isPending, isTrue);

    await tester.pump(const Duration(milliseconds: 299));
    expect(calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['query']);
    expect(debounce.isPending, isFalse);
  });

  testWidgets('a new call replaces the pending action and restarts the wait', (
    tester,
  ) async {
    final debounce = SearchDebounce();
    addTearDown(debounce.dispose);
    final calls = <String>[];

    debounce(() => calls.add('f'));
    await tester.pump(const Duration(milliseconds: 200));
    debounce(() => calls.add('fl'));
    await tester.pump(const Duration(milliseconds: 200));
    debounce(() => calls.add('flu'));

    await tester.pump(const Duration(milliseconds: 299));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['flu']);
  });

  testWidgets('cancel drops the pending action and is idempotent', (
    tester,
  ) async {
    final debounce = SearchDebounce();
    final calls = <String>[];

    debounce(() => calls.add('query'));
    debounce.cancel();
    debounce.cancel();
    expect(debounce.isPending, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty);
  });

  testWidgets('dispose stops a pending action from firing late', (
    tester,
  ) async {
    final debounce = SearchDebounce();
    final calls = <String>[];

    debounce(() => calls.add('query'));
    debounce.dispose();

    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty);
  });

  testWidgets('a custom delay is honoured', (tester) async {
    final debounce = SearchDebounce(delay: const Duration(milliseconds: 50));
    addTearDown(debounce.dispose);
    final calls = <String>[];

    debounce(() => calls.add('fast'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, ['fast']);
  });
}
