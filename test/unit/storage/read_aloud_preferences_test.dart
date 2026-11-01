import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/data/read_aloud/sqlite_read_aloud_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'follow defaults on, saves in order and survives reopening without changing other metadata',
    () async {
      final dir = await Directory.systemTemp.createTemp('read-aloud-pref-');
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.writeMetadata('other_preference', 'keep');
        final store = SqliteReadAloudPreferences(db);
        expect(await store.loadFollow(), isTrue);
        await Future.wait([
          store.saveFollow(false),
          store.saveFollow(true),
          store.saveFollow(false),
        ]);
        expect(await store.loadFollow(), isFalse);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(await SqliteReadAloudPreferences(db).loadFollow(), isFalse);
        expect(await db.readMetadata('other_preference'), 'keep');
        await SqliteReadAloudPreferences(db).saveFollow(true);
        expect(await SqliteReadAloudPreferences(db).loadFollow(), isTrue);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
