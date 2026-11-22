import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// Material defaults for the no-wave mobile experience.
///
/// The web's paper/ink/orange tokens are adapted to native controls instead of
/// replacing their focus, tap-target or screen-reader behaviour.
abstract final class AppTheme {
  static final lightThemeMode = _build(Brightness.light);
  static final darkThemeMode = _build(Brightness.dark);

  /// Every button's label. A button's text style replaces the inherited
  /// one instead of merging with it, so a style naming only the weight
  /// drops the family and the label falls back to the platform font
  /// (Roboto on Android) - which every button label did until this named it.
  static const buttonLabel = TextStyle(
    fontFamily: 'InterTight',
    fontWeight: FontWeight.w700,
  );

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? AppPalette.ink : AppPalette.paper;
    final foreground = dark ? AppPalette.paper : AppPalette.ink;
    final muted = dark ? AppPalette.mutedOnInk : AppPalette.mutedOnPaper;
    final surface = dark ? AppPalette.surfaceOnInk : AppPalette.surfaceOnPaper;
    final error = dark ? AppPalette.errorOnInk : AppPalette.oxblood;
    final tint = dark ? AppPalette.tintOnInk : AppPalette.tintOnPaper;
    final errorTint = dark
        ? AppPalette.errorTintOnInk
        : AppPalette.errorTintOnPaper;
    // The one primary fill of each theme: oxblood with paper on paper, orange
    // with ink on ink. Every filled button - NoWaveButton.primary, the
    // Material fallbacks and the floating action - uses this pair, so a page
    // never shows two different "main" colours.
    final primary = dark ? AppPalette.orange : AppPalette.oxblood;
    final onPrimary = dark ? AppPalette.ink : AppPalette.paper;
    // Every role is named. `copyWith` on the legacy light/dark schemes keeps
    // the roles it is not given at the old Material 2 defaults - purple
    // containers, teal tonal buttons - so anything left out here leaks a
    // colour that is not in the palette.
    final colorScheme =
        (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          primaryContainer: tint,
          onPrimaryContainer: foreground,
          inversePrimary: dark ? AppPalette.oxblood : AppPalette.orange,
          secondary: AppPalette.orange,
          onSecondary: AppPalette.ink,
          secondaryContainer: tint,
          onSecondaryContainer: foreground,
          tertiary: AppPalette.orange,
          onTertiary: AppPalette.ink,
          tertiaryContainer: tint,
          onTertiaryContainer: foreground,
          surface: background,
          surfaceDim: background,
          surfaceBright: background,
          onSurface: foreground,
          onSurfaceVariant: muted,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: background,
          surfaceContainerLow: background,
          surfaceContainer: surface,
          surfaceContainerHigh: surface,
          surfaceContainerHighest: surface,
          outline: muted,
          outlineVariant: foreground.withAlpha(NoWaveOpacity.dividerAlpha),
          inverseSurface: foreground,
          onInverseSurface: background,
          error: error,
          onError: dark ? AppPalette.ink : AppPalette.paper,
          errorContainer: errorTint,
          onErrorContainer: error,
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
      // A dialog is a card laid on the page: the same paper, square, no
      // shadow - so a hairline in the text colour is what lifts it off the
      // scrim, the way a printed card has an edge. Its title is set in the
      // serif of the section headings: a question to the reader is editorial
      // copy, not a system alert.
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(NoWaveRadius.none),
          ),
          side: BorderSide(color: foreground, width: NoWaveStroke.hairline),
        ),
        titleTextStyle: TextStyle(
          color: foreground,
          fontFamily: 'InstrumentSerif',
          fontFamilyFallback: NoWaveTypography.serifFallback,
          fontSize: NoWaveTypeScale.dialogTitle,
          fontWeight: FontWeight.w600,
          height: 1.3,
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
        // Titles start on the page gutter, so the masthead and a page title
        // line up with the column under them - on every page and platform.
        // A centred title (iOS's default, and what half the pages used to ask
        // for) floats free of the column and puts the masthead and a page
        // title on two different axes.
        centerTitle: false,
        titleSpacing: NoWaveSpacing.page,
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
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(
            NoWaveSizes.tapTarget,
            NoWaveSizes.primaryAction,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.large,
            vertical: NoWaveSpacing.small,
          ),
          textStyle: buttonLabel,
          shape: square,
        ),
      ),
      // Material's filled and outlined buttons default to a pill; the system
      // is square, so both are pinned here even where a screen uses them
      // directly instead of NoWaveButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(
            NoWaveSizes.tapTarget,
            NoWaveSizes.primaryAction,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.large,
            vertical: NoWaveSpacing.small,
          ),
          textStyle: buttonLabel,
          shape: square,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
          textStyle: buttonLabel,
          shape: square,
          side: BorderSide(color: foreground, width: NoWaveStroke.hairline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
          textStyle: buttonLabel,
          shape: square,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
      // A sheet rises from the bottom edge, so only its top edge needs the
      // hairline that a dialog carries all round.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        modalBackgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: Border(
          top: BorderSide(color: foreground, width: NoWaveStroke.hairline),
        ),
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
        side: BorderSide(color: muted, width: NoWaveStroke.hairline),
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
          textStyle: const WidgetStatePropertyAll<TextStyle?>(buttonLabel),
        ),
      ),
    );
  }
}
