import 'package:belog/core/theme/app_theme_mode.dart';

/// Persists the user's theme preference.
///
/// The port is deliberately plain Dart: it stores [AppThemeMode], not
/// Flutter's `ThemeMode`, so the persistence layer carries no UI type (#107).
/// Implementations live behind this interface (currently
/// `SqliteThemePreferenceStore`, backed by Drift/SQLite).
abstract interface class ThemePreferenceStore {
  Future<AppThemeMode> load();

  Future<void> save(AppThemeMode mode);
}
