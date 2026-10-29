import 'package:isar/isar.dart';

part 'theme_preference.g.dart';

/// Legacy Isar collection that mirrors the theme preference schema shipped in
/// older app versions.
///
/// This copy lives in the fixture generator only; keep it byte-compatible
/// with the app's `lib/core/storage/legacy/theme_preference.dart`. The class
/// name, property names and property ids must stay exactly as the old
/// generator produced them. The app copy imports `ThemeMode` from
/// `flutter/material.dart`; this package is pure Dart, so the enum is
/// redeclared below with the identical value order (`@enumerated` persists
/// the enum index, so the stored bytes match).
@collection
class ThemePreference {
  Id id = Isar.autoIncrement; // Primary key, auto-incremented

  @enumerated
  ThemeMode themeMode; // Store ThemeMode as an enum

  ThemePreference({required this.themeMode});
}

/// Value order must match `flutter.material.ThemeMode`.
enum ThemeMode { system, light, dark }
