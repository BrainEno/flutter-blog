import 'dart:io';

import 'package:belog/core/theme/theme_preference.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory directory;
  late Isar isar;

  Future<Isar> openDatabase() => Isar.open(
        [ThemePreferenceSchema, BlogDraftSchema],
        directory: directory.path,
        inspector: false,
      );

  setUpAll(() async {
    // Isar's test helper downloads its matching native binary only if it is
    // not already available. Only this test file initializes the native core.
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('belog-theme-test-');
    isar = await openDatabase();
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('first launch, repeated saves and restart use one persistent row',
      () async {
    var store = IsarThemePreferenceStore(isar);
    expect(await store.load(), ThemeMode.system);
    expect(await isar.themePreferences.count(), 0);
    await store.save(ThemeMode.light);
    await store.save(ThemeMode.dark);
    await store.save(ThemeMode.system);
    final preferences = await isar.themePreferences.where().findAll();
    expect(preferences, hasLength(1));
    expect(preferences.single.id, IsarThemePreferenceStore.preferenceId);
    expect(preferences.single.themeMode, ThemeMode.system);

    await isar.close();
    isar = await openDatabase();
    store = IsarThemePreferenceStore(isar);
    expect(await store.load(), ThemeMode.system);
    expect(await isar.themePreferences.count(), 1);
  });

  test('migrates the newest legacy preference without touching drafts',
      () async {
    await isar.writeTxn(() async {
      await isar.themePreferences
          .put(ThemePreference(themeMode: ThemeMode.light)..id = 2);
      await isar.themePreferences
          .put(ThemePreference(themeMode: ThemeMode.dark)..id = 9);
      await isar.themePreferences
          .put(ThemePreference(themeMode: ThemeMode.light)..id = 5);
      await isar.blogDrafts.put(BlogDraft(
        title: 'unsent',
        content: 'keep me',
        tags: const [],
        updatedAt: DateTime.utc(2024),
      ));
    });

    final store = IsarThemePreferenceStore(isar);
    expect(await store.load(), ThemeMode.dark);
    final preferences = await isar.themePreferences.where().findAll();
    expect(preferences, hasLength(1));
    expect(preferences.single.id, IsarThemePreferenceStore.preferenceId);
    expect(preferences.single.themeMode, ThemeMode.dark);
    expect((await isar.blogDrafts.where().findFirst())!.content, 'keep me');
    expect(await store.load(), ThemeMode.dark);
    expect(await isar.themePreferences.count(), 1);
  });

  test('new legacy writes after downgrade are migrated on the next launch',
      () async {
    var store = IsarThemePreferenceStore(isar);
    await store.save(ThemeMode.dark);
    await isar.writeTxn(() async {
      await isar.themePreferences
          .put(ThemePreference(themeMode: ThemeMode.light));
    });
    await isar.close();
    isar = await openDatabase();
    store = IsarThemePreferenceStore(isar);
    expect(await store.load(), ThemeMode.light);
    expect(await isar.themePreferences.count(), 1);
  });
}
