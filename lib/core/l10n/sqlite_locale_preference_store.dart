import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/storage/app_database.dart';

/// Stores the language choice in the existing `metadata` key/value table, so
/// the setting needs no schema migration.
class SqliteLocalePreferenceStore implements LocalePreferenceStore {
  static const String _key = 'app_language';

  final AppDatabase database;
  SqliteLocalePreferenceStore(this.database);

  @override
  Future<AppLanguage> load() async =>
      appLanguageFromStorageValue(await database.readMetadata(_key));

  @override
  Future<void> save(AppLanguage language) =>
      database.writeMetadata(_key, language.name);
}
