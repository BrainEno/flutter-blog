/// The theme preference in the storage layer's own language (#107).
///
/// The persisted row and the preference port below the UI speak this plain
/// Dart enum. `ThemeBloc` converts it to and from Flutter's `ThemeMode` at the
/// boundary, which is what lets the storage port stay free of UI types.
enum AppThemeMode {
  system,
  light,
  dark;

  /// Reads a stored name. Anything unrecognised - including a value written by
  /// a newer build - falls back to following the system, which is also the
  /// first-launch default.
  static AppThemeMode fromName(String? name) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return AppThemeMode.system;
  }
}
