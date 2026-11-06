import 'package:belog/core/design/design_tokens.dart';
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

    OutlineInputBorder border(
      Color color, {
      double width = NoWaveStroke.hairline,
    }) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(NoWaveRadius.none)),
      borderSide: BorderSide(color: color, width: width),
    );

    const square = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(NoWaveRadius.none)),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerColor: foreground.withAlpha(NoWaveOpacity.dividerAlpha),
      // Thickness only: the gap around a divider is layout, and pages that
      // want a compact rule already pass an explicit `height`.
      dividerTheme: DividerThemeData(
        color: foreground.withAlpha(NoWaveOpacity.dividerAlpha),
        thickness: NoWaveStroke.hairline,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: square,
        titleTextStyle: TextStyle(
          color: foreground,
          fontFamily: 'InterTight',
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: foreground,
          fontFamily: 'InterTight',
        ),
      ),
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
          horizontal: NoWaveSpacing.medium,
          vertical: NoWaveSpacing.medium,
        ),
        border: border(muted),
        enabledBorder: border(muted),
        focusedBorder: border(AppPalette.orange, width: NoWaveStroke.focus),
        errorBorder: border(error),
        focusedErrorBorder: border(error, width: NoWaveStroke.focus),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: foreground),
        errorStyle: TextStyle(color: error),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.orange,
          foregroundColor: AppPalette.ink,
          elevation: 0,
          minimumSize: const Size(
            NoWaveSizes.tapTarget,
            NoWaveSizes.primaryAction,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.large,
            vertical: NoWaveSpacing.small,
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: square,
        ),
      ),
      // Material's filled and outlined buttons default to a pill; the system
      // is square, so both are pinned here even where a screen uses them
      // directly instead of NoWaveButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            NoWaveSizes.tapTarget,
            NoWaveSizes.primaryAction,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.large,
            vertical: NoWaveSpacing.small,
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: square,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: square,
          side: BorderSide(color: foreground, width: NoWaveStroke.hairline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: square,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
        ),
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
        side: BorderSide(color: foreground, width: NoWaveStroke.hairline),
        shape: square,
      ),
      // The containers below are not all used by a screen today; they are
      // pinned here so the first screen that reaches for a sheet, a card, a
      // list tile or a segmented control does not reintroduce M3's rounded,
      // elevated, tinted defaults next to the editorial surfaces.
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: square,
      ),
      listTileTheme: ListTileThemeData(
        textColor: foreground,
        iconColor: muted,
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NoWaveSpacing.medium,
        ),
        shape: square,
        minTileHeight: NoWaveSizes.row,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        modalBackgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: square,
        dragHandleColor: muted,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? AppPalette.paper : AppPalette.ink,
        contentTextStyle: TextStyle(
          color: dark ? AppPalette.ink : AppPalette.paper,
          fontFamily: 'InterTight',
        ),
        actionTextColor: dark ? AppPalette.oxblood : AppPalette.orange,
        elevation: 0,
        shape: square,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : Colors.transparent,
        ),
        trackOutlineColor: WidgetStatePropertyAll<Color?>(muted),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: square,
        // Unchecked boxes are an outline, checked ones are a filled accent
        // square: the same rule the buttons follow.
        side: WidgetStateProperty.resolveWith<BorderSide?>(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : muted,
            width: NoWaveStroke.hairline,
          ),
        ),
        fillColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color?>(colorScheme.onPrimary),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.primary
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : foreground,
          ),
          side: WidgetStatePropertyAll<BorderSide?>(
            BorderSide(color: muted, width: NoWaveStroke.hairline),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder?>(square),
          minimumSize: const WidgetStatePropertyAll<Size?>(
            Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle?>(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
