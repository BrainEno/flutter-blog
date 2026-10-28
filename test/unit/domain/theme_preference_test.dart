import 'package:belog/core/theme/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemePreference Entity', () {
    test('should create ThemePreference with ThemeMode.light', () {
      final pref = ThemePreference(themeMode: ThemeMode.light);
      expect(pref.themeMode, ThemeMode.light);
    });

    test('should create ThemePreference with ThemeMode.dark', () {
      final pref = ThemePreference(themeMode: ThemeMode.dark);
      expect(pref.themeMode, ThemeMode.dark);
    });

    test('should create ThemePreference with ThemeMode.system', () {
      final pref = ThemePreference(themeMode: ThemeMode.system);
      expect(pref.themeMode, ThemeMode.system);
    });
  });
}