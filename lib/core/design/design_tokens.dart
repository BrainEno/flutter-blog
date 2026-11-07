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

  /// Cover aspect ratio of an article tile in a grid.
  static const coverAspect = 4 / 3;

  /// Cover aspect ratio of the feed's featured card and the reader header,
  /// where the image carries the page rather than a column.
  static const coverAspectWide = 16 / 10;

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

  /// How many columns the cold-start curtain is cut into.
  ///
  /// Six is the web loader's count; it is also the widest that still reads as
  /// separate columns on a 320dp screen.
  static const splashColumns = 6;

  /// The largest the counter may get. It is scaled down from here to fit the
  /// width, never clamped by a fixed height.
  static const splashCounterMax = 220.0;

  /// Share of the viewport width the counter's font size takes, before
  /// [splashCounterMax] caps it - the app's reading of the web's
  /// `min(30vw, 220px)`. It is a ratio, not a length, so a small phone gets
  /// smaller digits instead of overflowing ones.
  static const splashCounterViewport = 0.3;

  /// The wordmark on the curtain, and on the startup failure screen.
  static const splashWordmark = 40.0;

  /// The compact wordmark in an app bar.
  static const masthead = 22.0;

  /// Thickness of the decorative progress segment on the curtain.
  ///
  /// Decorative on purpose: it shows that something is happening, and it is
  /// not wired to any real progress figure.
  static const splashProgress = 3.0;

  /// How long the decorative segment is: wide enough to read as a rule, short
  /// enough not to look like a progress bar that is 18% done.
  static const splashProgressLength = 72.0;

  /// The short rule above a loading label: a printed mark, not a spinner.
  static const loadingRule = 40.0;

  /// Thickness of one skeleton line. Roughly the x-height of body copy, so a
  /// placeholder row is the height of the row it stands in for.
  static const skeletonLine = 12.0;
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

  /// A skeleton block: a shape that says "content is coming" without
  /// competing with the content it will be replaced by.
  static const skeletonAlpha = 28;
}

/// Motion. Short enough to feel like a native tap, long enough to be visible.
abstract final class NoWaveMotion {
  /// State change on the thing you touched (press, toggle).
  static const fast = Duration(milliseconds: 120);

  /// Content entering or leaving (a notice, a snackbar, a list rebuild).
  static const normal = Duration(milliseconds: 200);

  /// A page or sheet transition.
  static const slow = Duration(milliseconds: 320);

  /// Content entering: a reveal, a mask opening, a heading settling.
  ///
  /// Deliberately slower than [slow]: this is narrative, not feedback, and it
  /// must not read as a delay before the app is usable - it plays while the
  /// app behind it is already built.
  static const enter = Duration(milliseconds: 1000);

  /// A route transition.
  static const page = Duration(milliseconds: 900);

  /// One curtain column lifting in the cold-start sequence.
  static const curtain = Duration(milliseconds: 900);

  /// The counter's run from 000 to 088, before boot has reported.
  ///
  /// The number is choreography, not bytes: nothing measures it against a
  /// request, and the UI must never claim it is a real load percentage.
  static const counter = Duration(milliseconds: 1800);

  /// The last stretch, 088 to 100, once boot is finished.
  static const counterFinish = Duration(milliseconds: 350);

  /// How far apart two curtain columns start.
  static const stagger = Duration(milliseconds: 80);

  /// A splash shorter than this reads as a flicker, even when boot is instant.
  static const minimumSplash = Duration(milliseconds: 1400);

  /// Boot may hold the curtain no longer than this.
  ///
  /// A hung dependency must not leave the user on a loading screen: at this
  /// point the curtain lifts regardless and the app's own error states take
  /// over.
  static const splashBail = Duration(milliseconds: 4500);
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
