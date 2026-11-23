import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/viewer/reading_marks.dart';
import 'package:flutter_test/flutter_test.dart';

/// A history in memory, per account, that can hold back its next `list`.
class _History implements ReadingHistoryStore, UnattributedHistoryMaintenance {
  final progress = <String, Map<String, double?>>{};
  Completer<void>? gate;
  bool failList = false;
  bool unattributed = true;

  @override
  Future<void> record({required String userId, required Blog blog}) async {
    progress.putIfAbsent(userId, () => {}).putIfAbsent(blog.id, () => null);
  }

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async {
    final wait = gate;
    if (wait != null) await wait.future;
    if (failList) throw StateError('disk');
    return [
      for (final MapEntry(:key, :value) in (progress[userId] ?? {}).entries)
        ReadingHistoryEntry(
          blogId: key,
          title: key,
          posterName: '',
          imageUrl: '',
          readAt: DateTime.utc(2025),
          progress: value,
        ),
    ];
  }

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async {
    final entries = this.progress[userId];
    if (entries != null && entries.containsKey(blogId)) {
      entries[blogId] = progress;
    }
  }

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) async => progress[userId]?[blogId];

  @override
  Future<void> remove({required String userId, required String blogId}) async {
    progress[userId]?.remove(blogId);
  }

  @override
  Future<void> clear({required String userId}) async {
    progress.remove(userId);
  }

  @override
  Future<bool> hasUnattributedHistory() async => unattributed;

  @override
  Future<void> clearUnattributedHistory() async {
    unattributed = false;
  }
}

User _user(String id) =>
    User(id: id, email: '$id@example.com', name: id, updatedAt: DateTime(2025));

void main() {
  late _History history;
  late AppUserCubit users;
  late ReadingMarks marks;
  ReadingMarks? started;
  late int notified;

  setUp(() {
    history = _History()
      ..progress['ann'] = {'night-city': 0.42, 'rain': 0.99, 'opened': null}
      ..progress['bo'] = {'harbour': 0.6};
    users = AppUserCubit();
    notified = 0;
  });

  tearDown(() async {
    started?.dispose();
    started = null;
    await users.close();
  });

  void start() {
    marks = ReadingMarks(history, users: users)..addListener(() => notified++);
    started = marks;
  }

  test(
    "reads the signed-in reader's history once, and a guest has none",
    () async {
      start();
      await pumpEventQueue();
      expect(marks.progressFor('night-city'), isNull);

      users.updateUser(_user('ann'));
      await pumpEventQueue();
      expect(marks.progressFor('night-city'), 0.42);
      expect(marks.progressFor('rain'), 0.99);
      // Opened but never measured: nothing to mark.
      expect(marks.progressFor('opened'), isNull);
      expect(notified, 1);
    },
  );

  test(
    'a saved position moves the mark; the same percentage is silent',
    () async {
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();
      notified = 0;

      await marks.saveProgress(
        userId: 'ann',
        blogId: 'night-city',
        progress: 0.5,
      );
      expect(marks.progressFor('night-city'), 0.5);
      expect(history.progress['ann']!['night-city'], 0.5);
      expect(notified, 1);

      await marks.saveProgress(
        userId: 'ann',
        blogId: 'night-city',
        progress: 0.501,
      );
      expect(marks.progressFor('night-city'), 0.501);
      expect(notified, 1, reason: 'still "50% read"');

      // Past the end mark every position reads "Finished".
      await marks.saveProgress(userId: 'ann', blogId: 'rain', progress: 0.97);
      expect(notified, 1);
    },
  );

  test("another account's write never marks this reader's lists", () async {
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();
    notified = 0;

    await marks.saveProgress(userId: 'bo', blogId: 'harbour', progress: 0.9);
    expect(marks.progressFor('harbour'), isNull);
    expect(notified, 0);
  });

  test(
    'switching accounts drops the marks at once and reads the new ones',
    () async {
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();

      history.gate = Completer<void>();
      users.updateUser(_user('bo'));
      await pumpEventQueue();
      expect(marks.progressFor('night-city'), isNull);
      expect(marks.progressFor('harbour'), isNull);

      history.gate!.complete();
      history.gate = null;
      await pumpEventQueue();
      expect(marks.progressFor('harbour'), 0.6);

      users.updateUser(null);
      await pumpEventQueue();
      expect(marks.progressFor('harbour'), isNull);
    },
  );

  test('a slow read for the previous account is thrown away', () async {
    history.gate = Completer<void>();
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();

    users.updateUser(_user('bo'));
    final gate = history.gate!;
    history.gate = null;
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(marks.progressFor('night-city'), isNull);
    expect(marks.progressFor('harbour'), 0.6);
  });

  test('a profile update for the same reader keeps the marks', () async {
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();
    notified = 0;

    users.updateUser(_user('ann'));
    await pumpEventQueue();
    expect(marks.progressFor('night-city'), 0.42);
    expect(notified, 0);
  });

  test('a position saved while the history loads is not overwritten', () async {
    history.gate = Completer<void>();
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();

    await marks.saveProgress(
      userId: 'ann',
      blogId: 'night-city',
      progress: 0.7,
    );
    history.gate!.complete();
    await pumpEventQueue();

    expect(marks.progressFor('night-city'), 0.7);
  });

  test('removing an entry or clearing the history removes the marks', () async {
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();

    await marks.remove(userId: 'ann', blogId: 'night-city');
    expect(marks.progressFor('night-city'), isNull);
    expect(marks.progressFor('rain'), 0.99);

    await marks.clear(userId: 'ann');
    expect(marks.progressFor('rain'), isNull);
    expect(history.progress['ann'], isNull);
  });

  test('a history that cannot be read leaves the lists unmarked', () async {
    history.failList = true;
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();

    expect(marks.progressFor('night-city'), isNull);
    expect(notified, 0);
  });

  test('reads and pre-account maintenance pass straight through', () async {
    users.updateUser(_user('ann'));
    start();
    await pumpEventQueue();

    expect(await marks.progressOf(userId: 'ann', blogId: 'night-city'), 0.42);
    expect(await marks.list(userId: 'bo'), hasLength(1));
    expect(await marks.hasUnattributedHistory(), isTrue);
    await marks.clearUnattributedHistory();
    expect(await marks.hasUnattributedHistory(), isFalse);
  });

  test('the stages a position stands for', () {
    expect(ReadingProgress.stageOf(null), ReadingStage.unstarted);
    expect(ReadingProgress.stageOf(0.04), ReadingStage.unstarted);
    expect(ReadingProgress.stageOf(0.05), ReadingStage.partway);
    expect(ReadingProgress.stageOf(0.94), ReadingStage.partway);
    expect(ReadingProgress.stageOf(0.95), ReadingStage.finished);
    expect(ReadingProgress.stageOf(1), ReadingStage.finished);
  });
}
