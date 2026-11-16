import 'package:belog/features/blog/presentation/read_aloud/read_aloud_sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTimerHandle implements ReadAloudTimerHandle {
  FakeTimerHandle(this.callback);
  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

void main() {
  test('replacing, clearing and disposing a timer retires stale callbacks', () {
    final handles = <FakeTimerHandle>[];
    var now = DateTime(2026, 11, 16, 9);
    final timer = ReadAloudSleepTimer(
      now: () => now,
      scheduler: (delay, callback) {
        final handle = FakeTimerHandle(callback);
        handles.add(handle);
        return handle;
      },
    );
    var expirations = 0;
    timer.select(ReadAloudSleepTimerOption.fiveMinutes, () => expirations++);
    expect(timer.remaining, const Duration(minutes: 5));
    final first = handles.single;
    now = now.add(const Duration(minutes: 2));
    expect(timer.remaining, const Duration(minutes: 3));

    timer.select(ReadAloudSleepTimerOption.tenMinutes, () => expirations++);
    expect(first.cancelled, isTrue);
    first.callback();
    expect(expirations, 0);
    final second = handles.last;
    second.callback();
    expect(expirations, 1);
    expect(timer.option, ReadAloudSleepTimerOption.off);

    timer.select(ReadAloudSleepTimerOption.fifteenMinutes, () => expirations++);
    final third = handles.last;
    timer.clear();
    expect(third.cancelled, isTrue);
    third.callback();
    expect(expirations, 1);
    timer.dispose();
  });
}
