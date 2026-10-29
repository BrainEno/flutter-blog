import 'package:flutter/material.dart' show ThemeMode;
import 'package:isar/isar.dart';

part 'theme_preference.g.dart';

/// Legacy Isar collection that mirrors the theme preference schema shipped in
/// older app versions.
///
/// It exists only so [AppDatabase.importLegacyIfNeeded] can read databases
/// written before the SQLite migration. The class name, property names and
/// property ids must stay exactly as the old generator produced them. The
/// live theme store is Drift/SQLite.
@collection
class ThemePreference {
  Id id = Isar.autoIncrement; // Primary key, auto-incremented

  @enumerated
  ThemeMode themeMode; // Store ThemeMode as an enum

  ThemePreference({required this.themeMode});
}
