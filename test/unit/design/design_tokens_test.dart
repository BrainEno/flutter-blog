import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cheap invariants the token layer promises other screens. They are not a
/// style guide: each one is a property a screen or a test elsewhere relies on,
/// so breaking it should fail here before it shows up as a layout bug.
void main() {
  group('spacing', () {
    test('the scale is ordered and on the 4-point grid', () {
      final scale = [
        NoWaveSpacing.xs,
        NoWaveSpacing.small,
        NoWaveSpacing.medium,
        NoWaveSpacing.large,
        NoWaveSpacing.section,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(
          scale[i],
          greaterThan(scale[i - 1]),
          reason: 'step $i must be larger than the one before it',
        );
      }
      for (final step in scale) {
        expect(step % 4, 0, reason: '$step is off the 4-point grid');
      }
    });

    test('the page gutter is a real step of the same scale', () {
      expect(NoWaveSpacing.medium, NoWaveSpacing.page);
    });
  });

  group('geometry', () {
    test('corners are square except the cover badge', () {
      expect(NoWaveRadius.none, 0);
      expect(NoWaveRadius.badge, lessThanOrEqualTo(2));
    });

    test('every tappable component is at least 48pt tall', () {
      const mins = [NoWaveSizes.tapTarget, NoWaveSizes.primaryAction];
      for (final size in mins) {
        expect(size, greaterThanOrEqualTo(NoWaveSizes.tapTarget));
      }
      expect(NoWaveSizes.row, greaterThanOrEqualTo(NoWaveSizes.tapTarget));
    });

    test('the cover ratio matches the one article tiles use', () {
      expect(NoWaveSizes.coverAspect, closeTo(4 / 3, 1e-9));
    });

    test('row sizes keep their order and their tap target', () {
      // Component sizes are not spacing steps: the cover box is 250 and
      // primaryAction 52, and neither has to sit on the 4-point grid.
      expect(NoWaveSizes.emptyStateOffset % 4, 0);
      expect(
        NoWaveSizes.listThumbnailSmall,
        greaterThanOrEqualTo(NoWaveSizes.tapTarget),
        reason: 'a row thumbnail is also a touch target',
      );
      expect(
        NoWaveSizes.listThumbnail,
        greaterThan(NoWaveSizes.listThumbnailSmall),
      );
      expect(
        NoWaveSizes.coverEditorBox,
        greaterThan(NoWaveSizes.listThumbnail),
      );
    });
  });

  group('breakpoints', () {
    test('columns never go down as the window grows', () {
      var previous = 0;
      for (var width = 200.0; width <= 1600; width += 10) {
        final columns = NoWaveBreakpoints.columnsFor(width);
        expect(columns, greaterThanOrEqualTo(previous));
        previous = columns;
      }
    });

    test('the named widths switch at their own boundary', () {
      expect(NoWaveBreakpoints.columnsFor(NoWaveBreakpoints.medium - 1), 2);
      expect(NoWaveBreakpoints.columnsFor(NoWaveBreakpoints.medium), 3);
      expect(NoWaveBreakpoints.columnsFor(NoWaveBreakpoints.expanded - 1), 3);
      expect(NoWaveBreakpoints.columnsFor(NoWaveBreakpoints.expanded), 4);
    });
  });

  group('motion', () {
    test('durations stay short enough to read as feedback', () {
      expect(NoWaveMotion.fast, lessThan(NoWaveMotion.normal));
      expect(NoWaveMotion.normal, lessThan(NoWaveMotion.slow));
      expect(NoWaveMotion.slow.inMilliseconds, lessThanOrEqualTo(400));
    });
  });

  group('loading state', () {
    test('the placeholder parts sit on the same grid as the rows', () {
      expect(NoWaveSizes.skeletonLine % 4, 0);
      expect(NoWaveSizes.loadingRule % 4, 0);
    });

    test('a placeholder is quieter than a divider', () {
      expect(NoWaveOpacity.skeletonAlpha, lessThan(NoWaveOpacity.dividerAlpha));
      expect(NoWaveOpacity.skeletonAlpha, greaterThan(0));
    });
  });

  group('cold start', () {
    test('the floor is below the ceiling', () {
      expect(NoWaveMotion.minimumSplash, lessThan(NoWaveMotion.splashBail));
    });

    test('the whole opening fits inside the bail', () {
      // Counter, the last stretch, then every column, including the stagger.
      final columns =
          NoWaveMotion.curtain +
          NoWaveMotion.stagger * (NoWaveSizes.splashColumns - 1);
      final opening =
          NoWaveMotion.counter + NoWaveMotion.counterFinish + columns;
      expect(
        opening,
        lessThan(NoWaveMotion.splashBail),
        reason: 'a boot that hangs must still let the curtain finish lifting',
      );
    });

    test('the curtain reads as several columns, not two halves', () {
      expect(NoWaveSizes.splashColumns, greaterThanOrEqualTo(4));
      expect(
        NoWaveMotion.stagger * NoWaveSizes.splashColumns,
        lessThan(NoWaveMotion.curtain),
        reason: 'a stagger wider than one column turns the lift into a queue',
      );
    });

    test('the counter scales with the phone and caps on a window', () {
      double sizeFor(double width) {
        final scaled = width * NoWaveSizes.splashCounterViewport;
        return scaled < NoWaveSizes.splashCounterMax
            ? scaled
            : NoWaveSizes.splashCounterMax;
      }

      expect(sizeFor(320), closeTo(96, 1e-9));
      expect(sizeFor(2000), NoWaveSizes.splashCounterMax);
      expect(
        sizeFor(2000),
        greaterThan(sizeFor(360)),
        reason: 'the cap must not turn a tablet into a small phone',
      );
    });
  });

  group('the theme maps the tokens', () {
    for (final entry in {
      'light': AppTheme.lightThemeMode,
      'dark': AppTheme.darkThemeMode,
    }.entries) {
      final theme = entry.value;
      final label = entry.key;

      test('$label: buttons are square and keep the 48pt target', () {
        for (final style in [
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
        ]) {
          final shape = style?.shape?.resolve({});
          expect(
            shape,
            isA<RoundedRectangleBorder>(),
            reason: '$label buttons must not fall back to the M3 pill',
          );
          expect(
            (shape! as RoundedRectangleBorder).borderRadius,
            const BorderRadius.all(Radius.circular(NoWaveRadius.none)),
          );
          final minSize = style?.minimumSize?.resolve({});
          expect(minSize?.height, greaterThanOrEqualTo(NoWaveSizes.tapTarget));
        }
      });

      test('$label: dialogs share the page surface and the square corners', () {
        expect(
          theme.dialogTheme.backgroundColor,
          theme.scaffoldBackgroundColor,
        );
        final shape = theme.dialogTheme.shape;
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          const BorderRadius.all(Radius.circular(NoWaveRadius.none)),
        );
      });

      test('$label: inputs use the same hairline and focus weight', () {
        final input = theme.inputDecorationTheme;
        expect(
          (input.enabledBorder! as OutlineInputBorder).borderSide.width,
          NoWaveStroke.hairline,
        );
        expect(
          (input.focusedBorder! as OutlineInputBorder).borderSide.width,
          NoWaveStroke.focus,
        );
      });

      test('$label: containers are flat, square and on the page surface', () {
        expect(theme.cardTheme.elevation, 0);
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        expect(
          (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
          const BorderRadius.all(Radius.circular(NoWaveRadius.none)),
        );
        expect(
          theme.bottomSheetTheme.backgroundColor,
          theme.scaffoldBackgroundColor,
        );
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.listTileTheme.minTileHeight, NoWaveSizes.row);
        expect(theme.snackBarTheme.shape, isA<RoundedRectangleBorder>());
      });

      test('$label: selection controls follow the accent rule', () {
        expect(
          theme.checkboxTheme.fillColor?.resolve({WidgetState.selected}),
          theme.colorScheme.primary,
        );
        expect(theme.checkboxTheme.fillColor?.resolve({}), Colors.transparent);
        expect(
          theme.switchTheme.trackColor?.resolve({WidgetState.selected}),
          theme.colorScheme.primary,
        );
        final segmented = theme.segmentedButtonTheme.style;
        expect(
          segmented?.minimumSize?.resolve({})?.height,
          NoWaveSizes.tapTarget,
        );
        expect(
          segmented?.side?.resolve({WidgetState.selected})?.width,
          NoWaveStroke.hairline,
        );
        expect(
          segmented?.backgroundColor?.resolve({WidgetState.selected}),
          theme.colorScheme.primary,
        );
      });

      test('$label: the divider is the token opacity', () {
        expect(
          theme.dividerTheme.color,
          theme.colorScheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha),
        );
      });
    }
  });

  test('the palette keeps paper and ink as the only full-bleed surfaces', () {
    // A reminder that a new colour has to earn its place: the two theme
    // backgrounds are the brand's paper and ink, not a derived tint.
    expect(AppTheme.lightThemeMode.scaffoldBackgroundColor, AppPalette.paper);
    expect(AppTheme.darkThemeMode.scaffoldBackgroundColor, AppPalette.ink);
  });
}
