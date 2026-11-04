import 'dart:async';

import 'package:belog/core/nowave/session/single_flight.dart';
import 'package:flutter_test/flutter_test.dart';

/// A rotated refresh token may not be replayed, so one session rotates once no
/// matter how many callers ask at the same time.
void main() {
  test('callers with the same key share one operation', () async {
    final flights = KeyedSingleFlight<int>();
    final gate = Completer<void>();
    var calls = 0;

    Future<int> operation() async {
      calls++;
      await gate.future;
      return calls;
    }

    final first = flights.run(7, operation);
    final second = flights.run(7, operation);

    gate.complete();
    expect(await first, 1);
    expect(await second, 1);
    expect(calls, 1, reason: 'both callers shared one rotation');
  });

  test('a finished flight lets the next caller start again', () async {
    final flights = KeyedSingleFlight<int>();
    var calls = 0;

    Future<int> operation() async => ++calls;

    expect(await flights.run(1, operation), 1);
    expect(await flights.run(1, operation), 2);
  });

  test('a different key never joins the running flight', () async {
    final flights = KeyedSingleFlight<int>();
    final slowGate = Completer<void>();

    final older = flights.run(1, () async {
      await slowGate.future;
      return 1;
    });
    final newer = flights.run(2, () async => 2);

    // The new session must not wait for - or reuse - the old rotation.
    expect(await newer, 2);

    slowGate.complete();
    expect(await older, 1);
  });

  test('a failed flight releases its key', () async {
    final flights = KeyedSingleFlight<int>();

    await expectLater(
      flights.run(1, () async => throw StateError('rotation failed')),
      throwsStateError,
    );

    expect(await flights.run(1, () async => 5), 5);
  });

  test('finishing an older flight does not clear a newer slot', () async {
    final flights = KeyedSingleFlight<int>();
    final olderGate = Completer<void>();
    final newerGate = Completer<void>();
    var newerCalls = 0;

    Future<int> newerOperation() async {
      newerCalls++;
      await newerGate.future;
      return 2;
    }

    final older = flights.run(1, () async {
      await olderGate.future;
      return 1;
    });
    final newer = flights.run(2, newerOperation);
    final joined = flights.run(2, newerOperation);

    olderGate.complete();
    expect(await older, 1);

    newerGate.complete();
    expect(await newer, 2);
    expect(await joined, 2);
    expect(newerCalls, 1, reason: 'the newer slot survived the older flight');
  });
}
