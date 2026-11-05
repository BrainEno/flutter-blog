import 'package:belog/core/theme/app_theme_mode.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored names round-trip through the port', () {
    for (final mode in AppThemeMode.values) {
      expect(AppThemeMode.fromName(mode.name), mode);
    }
    // What actually lands in the `theme.mode` column. The names are the
    // storage format, so they must not drift with a UI rename.
    expect(AppThemeMode.values.map((mode) => mode.name), [
      'system',
      'light',
      'dark',
    ]);
  });

  test('an unknown or missing name falls back to following the system', () {
    expect(AppThemeMode.fromName('sepia'), AppThemeMode.system);
    expect(AppThemeMode.fromName(null), AppThemeMode.system);
    expect(AppThemeMode.fromName(''), AppThemeMode.system);
  });

  test('every stored mode maps onto the UI vocabulary', () {
    // The other direction (UI choice -> stored value) is asserted through the
    // fake store's writes in theme_bloc_test.dart.
    expect(AppThemeMode.system.themeMode, ThemeMode.system);
    expect(AppThemeMode.light.themeMode, ThemeMode.light);
    expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
  });
}
