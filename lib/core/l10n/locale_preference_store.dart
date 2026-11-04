import 'package:belog/core/l10n/app_language.dart';

/// Persists the in-app language choice.
///
/// Implementations live in the data layer (currently
/// [SqliteLocalePreferenceStore] backed by Drift/SQLite).
abstract interface class LocalePreferenceStore {
  Future<AppLanguage> load();

  Future<void> save(AppLanguage language);
}
