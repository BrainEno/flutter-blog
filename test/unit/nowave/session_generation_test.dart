import 'package:belog/core/nowave/session/session_generation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fence that decides whether an answer arriving after an await still
/// belongs to the account that asked for it.
void main() {
  test('every advance invalidates the fences captured before it', () {
    final generation = SessionGeneration();
    final captured = generation.value;

    expect(generation.isCurrent(captured), isTrue);

    generation.advance();
    expect(generation.isCurrent(captured), isFalse);
  });

  test('a fence stays current until the identity actually changes', () {
    final generation = SessionGeneration();
    final captured = generation.advance();

    expect(generation.value, captured);
    expect(generation.isCurrent(captured), isTrue);
    expect(generation.isCurrent(captured - 1), isFalse);
  });

  test('only the newest fence of several advances is current', () {
    final generation = SessionGeneration();
    final first = generation.advance();
    final second = generation.advance();
    final third = generation.advance();

    expect(generation.isCurrent(first), isFalse);
    expect(generation.isCurrent(second), isFalse);
    expect(generation.isCurrent(third), isTrue);
    expect(second, greaterThan(first));
    expect(third, greaterThan(second));
  });
}
