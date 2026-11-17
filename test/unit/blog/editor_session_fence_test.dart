import 'package:belog/features/blog/presentation/editor/editor_session_fence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fence = EditorSessionFence(userId: 'author', generation: 7);

  bool matches({
    String? user = 'author',
    String? active = 'author',
    String? token = 'token',
    int generation = 7,
  }) => fence.matches(
    displayedUserId: user,
    activeUserId: active,
    accessToken: token,
    currentGeneration: generation,
  );

  test('only the captured active user and generation are accepted', () {
    expect(matches(), isTrue);
    expect(matches(user: 'other'), isFalse);
    expect(matches(active: 'other'), isFalse);
    expect(matches(generation: 8), isFalse);
    expect(matches(token: null), isFalse);
    expect(matches(token: ''), isFalse);
    expect(matches(user: null), isFalse);
    expect(matches(active: null), isFalse);
  });

  test('invalid owner names cannot be accepted by matching invalid inputs', () {
    for (final owner in [null, '', ' author', 'author ']) {
      final invalid = EditorSessionFence(userId: owner, generation: 7);
      expect(
        invalid.matches(
          displayedUserId: owner,
          activeUserId: owner,
          accessToken: 'token',
          currentGeneration: 7,
        ),
        isFalse,
      );
    }
  });

  test(
    'a changed generation remains stale even for the same user and token',
    () {
      expect(matches(generation: 9), isFalse);
      expect(matches(generation: 6), isFalse);
    },
  );
}
