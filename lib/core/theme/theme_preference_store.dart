import 'package:flutter/material.dart';

/// Persists the user's theme preference.
///
/// Implementations live in the data layer (currently
/// [SqliteThemePreferenceStore] backed by Drift/SQLite).
abstract interface class ThemePreferenceStore {
  Future<ThemeMode> load();

  Future<void> save(ThemeMode mode);
}
