import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// Material defaults for the no-wave mobile experience.
///
/// The web's paper/ink/orange tokens are adapted to native controls instead of
/// replacing their focus, tap-target or screen-reader behaviour.
abstract final class AppTheme {
  static final lightThemeMode = _build(Brightness.light);
  static final darkThemeMode = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? AppPalette.ink : AppPalette.paper;
    final foreground = dark ? AppPalette.paper : AppPalette.ink;
    final muted = dark ? AppPalette.mutedOnInk : AppPalette.mutedOnPaper;
    final surface = dark ? AppPalette.surfaceOnInk : AppPalette.surfaceOnPaper;
    final error = dark ? AppPalette.errorOnInk : AppPalette.oxblood;
    final colorScheme =
        (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
          primary: dark ? AppPalette.orange : AppPalette.oxblood,
          onPrimary: dark ? AppPalette.ink : AppPalette.paper,
          secondary: AppPalette.orange,
          onSecondary: AppPalette.ink,
          surface: background,
          onSurface: foreground,
          onSurfaceVariant: muted,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: background,
          surfaceContainerLow: background,
          surfaceContainer: surface,
          surfaceContainerHigh: surface,
          surfaceContainerHighest: surface,
          outline: muted,
          error: error,
          onError: dark ? AppPalette.ink : AppPalette.paper,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: 'InterTight',
    );
    final textTheme = base.textTheme
        .apply(bodyColor: foreground, displayColor: foreground)
        .copyWith(
          bodySmall: base.textTheme.bodySmall?.copyWith(color: muted),
          titleSmall: base.textTheme.titleSmall?.copyWith(color: muted),
        );

    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerColor: foreground.withAlpha(100),
      dividerTheme: DividerThemeData(color: foreground.withAlpha(100)),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: foreground,
          fontFamily: 'InterTight',
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'InterTight',
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? foreground : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? foreground : muted);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border(muted),
        enabledBorder: border(muted),
        focusedBorder: border(AppPalette.orange, width: 2),
        errorBorder: border(error),
        focusedErrorBorder: border(error, width: 2),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: foreground),
        errorStyle: TextStyle(color: error),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.orange,
          foregroundColor: AppPalette.ink,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppPalette.orange,
        foregroundColor: AppPalette.ink,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: background,
        labelStyle: TextStyle(color: foreground),
        side: BorderSide(color: foreground),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }
}
