import 'package:flutter/widgets.dart';

/// The user's in-app language choice (issue #108).
///
/// [system] keeps following the device language - the behaviour the app had
/// before there was a setting - and the two explicit values pin the interface
/// regardless of the device.
enum AppLanguage { system, zh, en }

/// The `MaterialApp.locale` that implements [language].
///
/// Null means "follow the system": [resolveAppLocale] then picks the first
/// supported device language, keeping English region subtags for date and
/// number formatting.
Locale? localeFor(AppLanguage language) {
  switch (language) {
    case AppLanguage.system:
      return null;
    case AppLanguage.zh:
      return const Locale('zh', 'CN');
    case AppLanguage.en:
      return const Locale('en');
  }
}

/// Reads a persisted choice. Unknown or missing values fall back to
/// [AppLanguage.system] so a rolled-back or downgraded build keeps booting.
AppLanguage appLanguageFromStorageValue(String? value) {
  for (final language in AppLanguage.values) {
    if (language.name == value) return language;
  }
  return AppLanguage.system;
}
