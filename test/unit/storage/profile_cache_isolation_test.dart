import 'dart:convert';
import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

CachedProfile _profile(String name) => CachedProfile(
  displayName: name,
  avatarUrl: 'https://cdn.example.invalid/$name.webp',
  website: '',
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late Directory dir;
  late File file;
  late AppDatabase database;

  SqliteProfileCache cache(String origin) =>
      SqliteProfileCache(database, apiBaseUrl: Uri.parse(origin));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('belog-profile-cache-');
    file = File('${dir.path}/cache.sqlite');
    database = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test(
    'accounts and backends have separate profile rows after restart',
    () async {
      final first = cache('https://one.example.invalid/tenant/');
      final same = cache('https://one.example.invalid/tenant');
      final otherBackend = cache('https://two.example.invalid/tenant');
      await first.write(userId: 'account/A', profile: _profile('Alice'));
      await first.write(userId: 'account:B', profile: _profile('Bob'));
      await otherBackend.write(
        userId: 'account/A',
        profile: _profile('Elsewhere'),
      );

      expect((await same.read(userId: 'account/A'))?.displayName, 'Alice');
      expect((await first.read(userId: 'account:B'))?.displayName, 'Bob');
      expect(
        (await otherBackend.read(userId: 'account/A'))?.displayName,
        'Elsewhere',
      );
      expect(await otherBackend.read(userId: 'account:B'), isNull);

      await database.close();
      database = AppDatabase(NativeDatabase(file));
      final reopened = cache('https://one.example.invalid/tenant');
      expect((await reopened.read(userId: 'account/A'))?.displayName, 'Alice');
      expect((await reopened.read(userId: 'account:B'))?.displayName, 'Bob');
      await reopened.clear(userId: 'account/A');
      expect(await reopened.read(userId: 'account/A'), isNull);
      expect((await reopened.read(userId: 'account:B'))?.displayName, 'Bob');
      expect(
        (await cache(
          'https://two.example.invalid/tenant',
        ).read(userId: 'account/A'))?.displayName,
        'Elsewhere',
      );
    },
  );

  test(
    'unowned legacy data stays intact but is never assigned to an account',
    () async {
      final legacy = jsonEncode(_profile('Legacy').toJson());
      await database.writeMetadata('cached_profile_v1', legacy);
      final store = cache('https://one.example.invalid');

      expect(await store.read(userId: 'account-A'), isNull);
      expect(await store.read(userId: 'account-B'), isNull);
      await store.write(userId: 'account-A', profile: _profile('Alice'));
      await store.clear(userId: 'account-A');
      expect(await database.readMetadata('cached_profile_v1'), legacy);
    },
  );

  test('corrupt or invalid-shaped JSON is treated as a cache miss', () async {
    final store = cache('https://one.example.invalid');
    await store.write(userId: 'account-A', profile: _profile('Alice'));
    final row = await database
        .customSelect(
          "SELECT key FROM metadata WHERE key LIKE 'cached_profile_v2:%'",
        )
        .getSingle();
    final key = row.read<String>('key');
    await database.writeMetadata(key, '{not json');
    expect(await store.read(userId: 'account-A'), isNull);
    await database.writeMetadata(key, '{"updatedAt": 123}');
    expect(await store.read(userId: 'account-A'), isNull);
  });

  test('empty identities fail closed instead of sharing a cache key', () async {
    final store = cache('https://one.example.invalid');
    await expectLater(store.read(userId: ''), throwsArgumentError);
    await expectLater(
      Future<void>.sync(
        () => store.write(userId: '  ', profile: _profile('x')),
      ),
      throwsArgumentError,
    );
    await expectLater(
      Future<void>.sync(() => store.clear(userId: '')),
      throwsArgumentError,
    );
  });
}
