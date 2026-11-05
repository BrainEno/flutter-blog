import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/theme/app_theme_mode.dart';
import 'package:belog/core/theme/theme_preference_store.dart';

class SqliteThemePreferenceStore implements ThemePreferenceStore {
  final AppDatabase database;
  SqliteThemePreferenceStore(this.database);

  @override
  Future<AppThemeMode> load() async {
    final row = await database
        .customSelect('SELECT mode FROM theme WHERE id = 0')
        .getSingleOrNull();
    return AppThemeMode.fromName(row?.read<String>('mode'));
  }

  @override
  Future<void> save(AppThemeMode mode) => database.setTheme(mode.name);
}
