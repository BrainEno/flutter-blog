/// Design tokens for the no-wave mobile experience.
///
/// One source of truth for the numbers screens otherwise repeat: spacing,
/// corner radius, stroke, motion, icon size, tap target, breakpoints and the
/// opacity of non-semantic lines. Colours live next door in `AppPalette`
/// (paper/ink/orange/oxblood) because they are brand values, not geometry.
///
/// Rules that keep this file useful:
///
/// - **Screens read tokens; they do not invent numbers.** A `SizedBox(height:
///   8)` in a page is a missing token, not a style choice. If a screen needs a
///   value that is not here, add it here with a name that says what it means.
/// - **Names describe intent, not pixels.** `NoWaveSpacing.section` survives a
///   redesign; `24` does not.
/// - **Nothing here is a Material default.** These values describe the
///   editorial, square-cornered look; `AppTheme` maps them onto Material so a
///   widget that forgets to import this file still lands on the same grid.
///
/// See `docs/design-system.md` for the component catalogue and the
/// accessibility contract.
library;

/// Vertical and horizontal rhythm.
///
/// The scale is a 4-point grid with one editorial step (`section`) for the gap
/// between a page heading and its first block.
abstract final class NoWaveSpacing {
  /// 4: the gap between a label and the value it labels.
  static const xs = 4.0;

  /// 8: inside one group (a badge and its title, two lines of metadata).
  static const small = 8.0;

  /// 16: the page gutter, and the gap between two groups.
  static const medium = 16.0;

  /// 24: between a heading block and the content it introduces.
  static const large = 24.0;

  /// 32: between two sections of one page.
  static const section = 32.0;

  /// The page gutter. Same value as [medium], named for where it is used so a
  /// future redesign can widen gutters without touching group spacing.
  static const page = 16.0;
}

/// Corner radius. The design is square: badges get [badge], everything else
/// [none]. Circles come from shape, not radius (see `NoWaveAvatar`).
abstract final class NoWaveRadius {
  /// Square corners: buttons, inputs, cards, dialogs, sheets.
  static const none = 0.0;

  /// The only rounded corner in the system: a small overlay badge on a cover.
  /// 2 is deliberate - a 4pt radius already reads as "Material chip".
  static const badge = 2.0;
}

/// Line weights.
abstract final class NoWaveStroke {
  /// A hairline: dividers, input borders, badge outlines.
  static const hairline = 1.0;

  /// Focus rings and the selected border of a focused input.
  static const focus = 2.0;
}

/// Icon sizes, aligned with the type scale they sit next to.
abstract final class NoWaveIconSize {
  /// Inline with metadata text.
  static const inline = 18.0;

  /// Trailing affordance inside a row (chevron, overflow).
  static const row = 20.0;

  /// Leading icon of an action row, or a lone icon button glyph.
  static const action = 22.0;

  /// Empty-state and dialog glyphs.
  static const display = 48.0;
}

/// Component sizes that are not spacing.
abstract final class NoWaveSizes {
  /// Minimum touch target. Material's 48dp, restated so tests and new
  /// components have one number to check against.
  static const tapTarget = 48.0;

  /// Height of a full-width primary action.
  static const primaryAction = 52.0;

  /// Minimum height of a tappable list row.
  static const row = 64.0;

  /// Cover aspect ratio used by every article tile and header.
  static const coverAspect = 4 / 3;

  /// Widest a paragraph column may get before it is centred on a tablet, so
  /// long lines stay readable.
  static const maxReadingWidth = 720.0;

  /// Fixed cover box in the editor.
  ///
  /// The three states (picked file, pending bytes, published URL) draw the
  /// same frame, so the form does not jump when the cover changes.
  static const coverEditorBox = 250.0;

  /// How far an empty or loading state starts below the top of its list.
  ///
  /// Not a spacing step: it says where the state begins, not how two things
  /// relate, and every list that shows one starts in the same place.
  static const emptyStateOffset = 48.0;

  /// Leading thumbnail of a list row (reading history, recycling bin).
  static const listThumbnail = 56.0;

  /// The smaller leading thumbnail used where the row also carries actions.
  static const listThumbnailSmall = 48.0;
}

/// Opacity of lines and overlays that are not semantic colours.
///
/// Expressed as alpha bytes because the design paints them over whatever
/// surface the theme picked, rather than as a fixed grey.
abstract final class NoWaveOpacity {
  /// Dividers and hairlines: 39% of the foreground.
  static const dividerAlpha = 100;

  /// Focus/hover wash: 22% of the accent.
  static const focusAlpha = 55;

  /// A disabled control.
  static const disabledAlpha = 97;
}

/// Motion. Short enough to feel like a native tap, long enough to be visible.
abstract final class NoWaveMotion {
  /// State change on the thing you touched (press, toggle).
  static const fast = Duration(milliseconds: 120);

  /// Content entering or leaving (a notice, a snackbar, a list rebuild).
  static const normal = Duration(milliseconds: 200);

  /// A page or sheet transition.
  static const slow = Duration(milliseconds: 320);
}

/// Layout breakpoints and the grid they imply.
abstract final class NoWaveBreakpoints {
  /// Two columns below this width.
  static const medium = 600.0;

  /// Three columns from [medium]; four from [expanded].
  static const expanded = 900.0;

  /// How many article tiles fit side by side at [width].
  ///
  /// Kept here - not inside the grid widget - so a list, a skeleton and a
  /// future tablet rail agree on the same answer.
  static int columnsFor(double width) {
    if (width >= expanded) return 4;
    if (width >= medium) return 3;
    return 2;
  }
}
