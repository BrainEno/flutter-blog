import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';

class SqliteThemePreferenceStore implements ThemePreferenceStore {
  final AppDatabase database;
  SqliteThemePreferenceStore(this.database);

  @override
  Future<ThemeMode> load() async {
    final row = await database
        .customSelect('SELECT mode FROM theme WHERE id = 0')
        .getSingleOrNull();
    final name = row?.read<String>('mode');
    return ThemeMode.values.where((mode) => mode.name == name).firstOrNull ??
        ThemeMode.system;
  }

  @override
  Future<void> save(ThemeMode mode) => database.setTheme(mode);
}
