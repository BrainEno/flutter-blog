import 'package:belog/core/theme/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

abstract interface class ThemePreferenceStore {
  Future<ThemeMode> load();
  Future<void> save(ThemeMode mode);
}

/// Keeps a single preference in the existing Isar collection, without a schema
/// change. Legacy rows used auto-incrementing IDs, so the highest ID is the
/// most recently written preference.
class IsarThemePreferenceStore implements ThemePreferenceStore {
  static const preferenceId = 0;
  final Isar isar;

  IsarThemePreferenceStore(this.isar);

  @override
  Future<ThemeMode> load() async {
    return isar.writeTxn(() async {
      // Isar only applies where-sort to an explicit index clause. Without
      // anyId(), a plain collection scan can still return the oldest row.
      final latest = await isar.themePreferences
          .where(sort: Sort.desc)
          .anyId()
          .findFirst();
      if (latest == null) return ThemeMode.system;

      if (latest.id != preferenceId) {
        // Write the chosen value before removing legacy rows, in one atomic
        // transaction. No other collection (including drafts) is touched.
        final migrated = ThemePreference(themeMode: latest.themeMode)
          ..id = preferenceId;
        await isar.themePreferences.put(migrated);
        await isar.themePreferences
            .where()
            .idNotEqualTo(preferenceId)
            .deleteAll();
      }
      return latest.themeMode;
    });
  }

  @override
  Future<void> save(ThemeMode mode) async {
    await isar.writeTxn(() async {
      final preference = ThemePreference(themeMode: mode)..id = preferenceId;
      await isar.themePreferences.put(preference);
      // Also handle legacy rows that may have been created by a downgraded app.
      await isar.themePreferences
          .where()
          .idNotEqualTo(preferenceId)
          .deleteAll();
    });
  }
}
