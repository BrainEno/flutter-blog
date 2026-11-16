import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/read_aloud/sqlite_read_aloud_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reader settings default safely, save in order and survive reopening without changing other metadata',
    () async {
      final dir = await Directory.systemTemp.createTemp('read-aloud-pref-');
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.writeMetadata('other_preference', 'keep');
        final store = SqliteReadAloudPreferences(db);
        expect((await store.load()).follow, isTrue);
        expect((await store.load()).speed, 1);
        await Future.wait([
          store.saveFollow(false),
          store.saveSpeed(1.5),
          store.savePreferredVoice('en_us', 'system-English'),
          store.savePreferredVoice('zh-CN', '系统中文'),
          store.savePreferredVoice('en-US', 'system-English-2'),
        ]);
        final saved = await store.load();
        expect(saved.follow, isFalse);
        expect(saved.speed, 1.5);
        expect(saved.preferredVoiceIds, {
          'en-US': 'system-English-2',
          'zh-CN': '系统中文',
        });
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final reopened = await SqliteReadAloudPreferences(db).load();
        expect(reopened.follow, isFalse);
        expect(reopened.speed, 1.5);
        expect(reopened.preferredVoiceIdFor('EN_us'), 'system-English-2');
        expect(await db.readMetadata('other_preference'), 'keep');
        await SqliteReadAloudPreferences(db).savePreferredVoice('en-US', null);
        await SqliteReadAloudPreferences(
          db,
        ).saveSpeed(9); // Invalid -> default.
        final changed = await SqliteReadAloudPreferences(db).load();
        expect(changed.preferredVoiceIdFor('en-US'), isNull);
        expect(changed.speed, 1);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'malformed old metadata does not hide local reader preferences',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.writeMetadata('read_aloud_follow_v1', '0');
      await db.writeMetadata('read_aloud_speed_v1', 'not-a-rate');
      await db.writeMetadata('read_aloud_voices_v1', '{bad JSON');
      final settings = await SqliteReadAloudPreferences(db).load();
      expect(settings.follow, isFalse);
      expect(settings.speed, 1);
      expect(settings.preferredVoiceIds, isEmpty);
    },
  );
}
