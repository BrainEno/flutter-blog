import 'dart:async';
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/datasources/sqlite_recent_search_store.dart';
import 'package:belog/features/blog/domain/repositories/recent_search_store.dart';
import 'package:belog/features/blog/presentation/search/recent_searches.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recent searches in memory, per account, that can hold back its next load.
class _Store implements RecentSearchStore {
  final saved = <String, List<String>>{};
  final saves = <String>[];
  Completer<void>? gate;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<List<String>> load({required String userId}) async {
    final wait = gate;
    if (wait != null) await wait.future;
    if (failLoad) throw StateError('disk');
    return saved[userId] ?? const [];
  }

  @override
  Future<void> save({
    required String userId,
    required List<String> queries,
  }) async {
    saves.add(userId);
    if (failSave) throw StateError('disk');
    saved[userId] = queries;
  }
}

User _user(String id) =>
    User(id: id, email: '$id@example.com', name: id, updatedAt: DateTime(2025));

void main() {
  group('rememberSearch', () {
    test('puts the query on top, trimmed, without an earlier copy', () {
      expect(rememberSearch(const ['wall', 'rain'], '  rain  '), [
        'rain',
        'wall',
      ]);
    });

    test('treats a different case as the same search, keeping the new', () {
      expect(rememberSearch(const ['Wall', 'rain'], 'wall'), ['wall', 'rain']);
    });

    test('ignores a blank query', () {
      const recent = ['wall'];
      expect(identical(rememberSearch(recent, '   '), recent), isTrue);
    });

    test('keeps at most the limit, dropping the oldest', () {
      var recent = const <String>[];
      for (var i = 0; i < AppLimits.recentSearches + 3; i++) {
        recent = rememberSearch(recent, 'q$i');
      }
      expect(recent, hasLength(AppLimits.recentSearches));
      expect(recent.first, 'q${AppLimits.recentSearches + 2}');
      expect(recent, isNot(contains('q0')));
    });

    test('forgetSearch drops every spelling of the query', () {
      expect(forgetSearch(const ['Wall', 'rain'], ' wall '), ['rain']);
    });
  });

  group('RecentSearches', () {
    late _Store store;
    late AppUserCubit users;
    RecentSearches? started;
    late RecentSearches recent;
    late int notified;

    setUp(() {
      store = _Store()
        ..saved['ann'] = ['巡逻队', 'wall']
        ..saved['bo'] = ['harbour'];
      users = AppUserCubit();
      notified = 0;
    });

    tearDown(() async {
      started?.dispose();
      started = null;
      await users.close();
    });

    void start() {
      recent = RecentSearches(store, users: users)
        ..addListener(() => notified++);
      started = recent;
    }

    test("reads the signed-in reader's searches; a guest has none", () async {
      start();
      await pumpEventQueue();
      expect(recent.queries, isEmpty);

      users.updateUser(_user('ann'));
      await pumpEventQueue();
      expect(recent.queries, ['巡逻队', 'wall']);
      expect(notified, 1);
    });

    test('a guest search is not kept anywhere', () async {
      start();
      recent.remember('secret');
      await recent.settled;
      expect(recent.queries, isEmpty);
      expect(store.saves, isEmpty);
    });

    test('remember, remove and clear apply at once and are saved', () async {
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();

      recent.remember('rain');
      expect(recent.queries, ['rain', '巡逻队', 'wall']);
      recent.remember('WALL');
      expect(recent.queries, ['WALL', 'rain', '巡逻队']);
      recent.remove('巡逻队');
      expect(recent.queries, ['WALL', 'rain']);
      await recent.settled;
      expect(store.saved['ann'], ['WALL', 'rain']);

      final before = recent.queries;
      recent.clear();
      expect(recent.queries, isEmpty);
      await recent.settled;
      expect(store.saved['ann'], isEmpty);

      recent.remember('new');
      recent.restore(before);
      expect(recent.queries, ['new', 'WALL', 'rain']);
      await recent.settled;
      expect(store.saved['ann'], ['new', 'WALL', 'rain']);
    });

    test('a change that shows nothing new does not notify', () async {
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();
      final heard = notified;
      recent.remember('巡逻队');
      recent.remove('not there');
      expect(notified, heard);
    });

    test('an account change swaps the list and drops a slow read', () async {
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();
      expect(recent.queries, ['巡逻队', 'wall']);

      store.gate = Completer<void>();
      users.updateUser(_user('bo'));
      await pumpEventQueue();
      // The previous reader's searches are gone before the next ones load.
      expect(recent.queries, isEmpty);

      users.updateUser(null);
      await pumpEventQueue();
      store.gate!.complete();
      await pumpEventQueue();
      // Bo's read finished after sign-out: it must not appear.
      expect(recent.queries, isEmpty);
    });

    test('a search made while the read is in flight stays on top', () async {
      store.gate = Completer<void>();
      users.updateUser(_user('ann'));
      start();
      recent.remember('rain');
      recent.remember('wall');
      recent.remove('wall');
      store.gate!.complete();
      await pumpEventQueue();
      await recent.settled;
      // Removed while loading: it does not come back from the saved list.
      expect(recent.queries, ['rain', '巡逻队']);
      expect(store.saved['ann'], ['rain', '巡逻队']);
    });

    test('clearing while the read is in flight keeps it clear', () async {
      store.gate = Completer<void>();
      users.updateUser(_user('ann'));
      start();
      recent.remember('rain');
      recent.clear();
      store.gate!.complete();
      await pumpEventQueue();
      await recent.settled;
      expect(recent.queries, isEmpty);
      expect(store.saved['ann'], isEmpty);
    });

    test('storage failures leave a working list', () async {
      store
        ..failLoad = true
        ..failSave = true;
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();
      expect(recent.queries, isEmpty);
      recent.remember('rain');
      await recent.settled;
      expect(recent.queries, ['rain']);
    });

    test('nothing changes after dispose', () async {
      users.updateUser(_user('ann'));
      start();
      await pumpEventQueue();
      started = null;
      recent.dispose();
      recent
        ..remember('late')
        ..remove('wall')
        ..clear()
        ..restore(const ['x']);
      expect(recent.queries, ['巡逻队', 'wall']);
    });

    test('rememberAll keeps order, drops repeats and caps', () {
      expect(RecentSearches.rememberAll(const ['a', 'b', 'A', 'c']), [
        'a',
        'b',
        'c',
      ]);
      expect(
        RecentSearches.rememberAll([
          for (var i = 0; i < AppLimits.recentSearches + 2; i++) 'q$i',
        ]),
        hasLength(AppLimits.recentSearches),
      );
    });
  });

  group('SqliteRecentSearchStore', () {
    late Directory dir;
    late AppDatabase db;
    late SqliteRecentSearchStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('belog-recent-');
      db = AppDatabase(NativeDatabase(File('${dir.path}/recent.sqlite')));
      store = SqliteRecentSearchStore(
        db,
        apiBaseUrl: Uri.parse('https://api.example.invalid'),
      );
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('keeps each account apart and round-trips the order', () async {
      await store.save(userId: 'ann', queries: const ['巡逻队', 'wall']);
      await store.save(userId: 'bo', queries: const ['harbour']);
      expect(await store.load(userId: 'ann'), ['巡逻队', 'wall']);
      expect(await store.load(userId: 'bo'), ['harbour']);
      expect(await store.load(userId: 'cy'), isEmpty);
    });

    test('another backend does not see the searches', () async {
      await store.save(userId: 'ann', queries: const ['wall']);
      final other = SqliteRecentSearchStore(
        db,
        apiBaseUrl: Uri.parse('https://other.example.invalid'),
      );
      expect(await other.load(userId: 'ann'), isEmpty);
    });

    test('an empty list removes the row', () async {
      await store.save(userId: 'ann', queries: const ['wall']);
      await store.save(userId: 'ann', queries: const []);
      expect(await db.readMetadata(store.keyFor('ann')), isNull);
    });

    test('a damaged or foreign value reads as a clean list', () async {
      await db.writeMetadata(store.keyFor('ann'), 'not json');
      expect(await store.load(userId: 'ann'), isEmpty);
      await db.writeMetadata(store.keyFor('ann'), '{"a":1}');
      expect(await store.load(userId: 'ann'), isEmpty);
      await db.writeMetadata(
        store.keyFor('ann'),
        '[" wall ", 3, "Wall", "rain", "", ${List.generate(12, (i) => '"q$i"').join(', ')}]',
      );
      final loaded = await store.load(userId: 'ann');
      expect(loaded.take(2), ['wall', 'rain']);
      expect(loaded, hasLength(AppLimits.recentSearches));
    });
  });
}
