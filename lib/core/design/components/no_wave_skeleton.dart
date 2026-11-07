import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// A placeholder with the shape of the content that is coming.
///
/// Two rules, both learned from spinners:
///
/// - **It is shaped like the content.** The point is that nothing jumps when
///   the real rows arrive, so the placeholder borrows the row height and the
///   thumbnail size of the list it stands in for rather than inventing its own
///   geometry.
/// - **It does not move.** No shimmer, no gradient sweep: motion is the one
///   thing a loading state should not spend the user's attention on, and the
///   app's motion policy (not a widget) decides when something animates. A
///   static block also reads correctly in a screenshot.
///
/// Everything below the wrapper is excluded from semantics and the wrapper
/// announces once, so a screen reader hears the loading sentence instead of
/// "rectangle" twenty times.
class NoWaveSkeleton extends StatelessWidget {
  const NoWaveSkeleton({super.key, this.semanticLabel, required this.child});

  /// What a screen reader announces once for the whole placeholder.
  /// Defaults to the generic loading label.
  final String? semanticLabel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? context.l10n.loading,
      liveRegion: true,
      child: ExcludeSemantics(child: child),
    );
  }
}

/// The fill of every placeholder part. Drawn from the surface's own foreground
/// so it works on paper and on ink without a second palette.
Color _fill(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withAlpha(
      NoWaveOpacity.skeletonAlpha,
    );

/// The hairline between two placeholder rows, the same weight as a real
/// divider.
Color _hairline(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withAlpha(
      NoWaveOpacity.dividerAlpha,
    );

/// One line of placeholder text.
class NoWaveSkeletonLine extends StatelessWidget {
  const NoWaveSkeletonLine({super.key, this.widthFactor = 1});

  /// Share of the available width, so a paragraph keeps its ragged edge
  /// instead of looking like a form field.
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: SizedBox(
        height: NoWaveSizes.skeletonLine,
        child: ColoredBox(color: _fill(context)),
      ),
    );
  }
}

/// One block: a cover, a thumbnail, an avatar frame.
class NoWaveSkeletonBlock extends StatelessWidget {
  const NoWaveSkeletonBlock({super.key, this.width, this.height, this.square});

  final double? width;

  final double? height;

  /// Convenience for the square cases (thumbnails, avatar frames).
  final double? square;

  @override
  Widget build(BuildContext context) {
    final side = square;
    return SizedBox(
      width: side ?? width,
      height: side ?? height,
      child: ColoredBox(color: _fill(context)),
    );
  }
}

/// Placeholder rows for a list screen: the same rhythm as a real row, so the
/// page does not reflow when the data lands.
class NoWaveSkeletonList extends StatelessWidget {
  const NoWaveSkeletonList({
    super.key,
    this.rows = 4,
    this.thumbnails = true,
    this.semanticLabel,
  });

  final int rows;

  /// Article-ish lists have a leading thumbnail; settings and message rows do
  /// not.
  final bool thumbnails;

  final String? semanticLabel;

  /// Widths of the three lines in one row, as a share of the text column: a
  /// title, a subtitle and a short meta line.
  static const _lineWidths = [1.0, 0.72, 0.36];

  @override
  Widget build(BuildContext context) {
    return NoWaveSkeleton(
      semanticLabel: semanticLabel,
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < rows; row++) _row(context, row),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (index > 0)
          SizedBox(
            height: NoWaveStroke.hairline,
            child: ColoredBox(color: _hairline(context)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.page,
            vertical: NoWaveSpacing.medium,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbnails) ...[
                const NoWaveSkeletonBlock(square: NoWaveSizes.listThumbnail),
                const SizedBox(width: NoWaveSpacing.medium),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var line = 0; line < _lineWidths.length; line++) ...[
                      NoWaveSkeletonLine(widthFactor: _lineWidths[line]),
                      if (line < _lineWidths.length - 1)
                        const SizedBox(height: NoWaveSpacing.small),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
