import 'dart:io';

import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/sqlite_locale_preference_store.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the language choice defaults to system, survives reopening and leaves other metadata alone',
    () async {
      final dir = await Directory.systemTemp.createTemp('locale-pref-');
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.writeMetadata('other_preference', 'keep');
        expect(
          await SqliteLocalePreferenceStore(db).load(),
          AppLanguage.system,
        );

        await SqliteLocalePreferenceStore(db).save(AppLanguage.en);
        expect(await SqliteLocalePreferenceStore(db).load(), AppLanguage.en);

        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(await SqliteLocalePreferenceStore(db).load(), AppLanguage.en);
        expect(await db.readMetadata('other_preference'), 'keep');

        // A value written by a newer build must not brick an older one.
        await db.writeMetadata('app_language', 'cl');

        expect(
          await SqliteLocalePreferenceStore(db).load(),
          AppLanguage.system,
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
