import 'dart:async';

import 'package:belog/core/nowave/session/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// Persistence must land in call order: a slow write for the previous account
/// may not finish after the sign-out or after the next account's write.
void main() {
  test('operations run one at a time, in call order', () async {
    final queue = SerialQueue();
    final log = <String>[];
    final gate = Completer<void>();

    final first = queue.run(() async {
      log.add('first-start');
      await gate.future;
      log.add('first-end');
      return 1;
    });
    final second = queue.run(() async {
      log.add('second');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(log, ['first-start'], reason: 'the second call waits its turn');

    gate.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(log, ['first-start', 'first-end', 'second']);
  });

  test('a failed operation does not block the ones behind it', () async {
    final queue = SerialQueue();

    final failed = queue.run<int>(() async {
      throw StateError('storage down');
    });
    final next = queue.run(() async => 7);

    await expectLater(failed, throwsStateError);
    expect(await next, 7);
  });

  test('each caller keeps its own result and error', () async {
    final queue = SerialQueue();
    final results = <int>[];

    Future<void> record(Future<int> value) async => results.add(await value);

    final first = record(queue.run(() async => 1));
    final failing = queue.run<int>(() async {
      throw StateError('boom');
    });
    final second = record(queue.run(() async => 3));

    await first;
    await expectLater(failing, throwsStateError);
    await second;

    expect(results, [1, 3]);
  });
}
