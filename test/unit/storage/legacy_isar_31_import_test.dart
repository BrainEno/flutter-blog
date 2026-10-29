import 'dart:io';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart' as isar_community;

/// Reads a database committed as written by the abandoned `isar 3.1.0+1`
/// (see `tool/legacy_isar_fixture`) to prove the isar_community-based reader
/// keeps old user data readable after the issue #3 migration.
void main() {
  setUpAll(() => isar_community.Isar.initializeIsarCore(download: true));

  test('imports a database written by the original isar 3.1.0+1', () async {
    final fixture = File('test/fixtures/legacy_isar_3_1_0/default.isar');
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'run tool/legacy_isar_fixture to regenerate the fixture',
    );
    final fixtureBytes = await fixture.readAsBytes();
    final dir = await Directory.systemTemp.createTemp('belog-legacy-31-');
    final db = AppDatabase(NativeDatabase(File('${dir.path}/new.sqlite')));
    try {
      await fixture.copy('${dir.path}/default.isar');
      await db.importLegacyIfNeeded(dir);
      // The original file must stay untouched so a downgrade keeps working.
      expect(
        await File('${dir.path}/default.isar').readAsBytes(),
        fixtureBytes,
      );
      // Highest theme id wins, drafts keep their scoping, cache is filled.
      expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.dark);
      expect((await SqliteBlogDraftStore(db).load('a'))!.content, 'unsent');
      expect((await SqliteBlogDraftStore(db).load(null))!.title, 'new article');
      expect(
        (await SqliteBlogCache(db).loadBlogs()).single.posterName,
        'Alice',
      );
      // The completion marker prevents a second import from overwriting
      // newer local writes.
      await SqliteThemePreferenceStore(db).save(ThemeMode.light);
      await db.importLegacyIfNeeded(dir);
      expect(await SqliteThemePreferenceStore(db).load(), ThemeMode.light);
      expect(
        await File('${dir.path}/default.isar').readAsBytes(),
        fixtureBytes,
      );
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
