import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:flutter/material.dart';

/// Placeholder tiles for an article grid.
///
/// The tile's geometry is the real grid's: columns and height come from
/// [blogGridDelegate], and the cover keeps `NoWaveSizes.coverAspect`, so the
/// covers land exactly where the articles will and the page does not reflow
/// when the data arrives.
///
/// Everything is excluded from semantics; the wrapper announces
/// [semanticLabel] once (see [NoWaveSkeleton]). There is no shimmer: the app's
/// motion policy decides when something moves, and a loading state is not the
/// place to spend the reader's attention.
class BlogGridSkeleton extends StatelessWidget {
  const BlogGridSkeleton({
    super.key,
    this.tiles = 6,
    this.padding,
    this.semanticLabel,
  });

  /// How many placeholder tiles to draw.
  final int tiles;

  /// Defaults to the grid's own: a `GridView` with no padding honours the
  /// media padding, which is what the real grid on the page does.
  final EdgeInsets? padding;

  /// What a screen reader hears once, in place of the shapes.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return NoWaveSkeleton(
      semanticLabel: semanticLabel,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: blogGridDelegate(context),
        itemCount: tiles,
        itemBuilder: (context, index) => const _GridTileSkeleton(),
      ),
    );
  }
}

/// One tile: cover, a two-line title, a description line and a meta line.
class _GridTileSkeleton extends StatelessWidget {
  const _GridTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AspectRatio(
          aspectRatio: NoWaveSizes.coverAspect,
          child: NoWaveSkeletonBlock(),
        ),
        const SizedBox(height: NoWaveSpacing.small),
        // The text area has a fixed share of the tile, so the lines sit at the
        // top of it and the block below absorbs whatever slack the tile has.
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              NoWaveSkeletonLine(widthFactor: 0.9),
              SizedBox(height: NoWaveSpacing.xs),
              NoWaveSkeletonLine(widthFactor: 0.5),
              SizedBox(height: NoWaveSpacing.xs),
              NoWaveSkeletonLine(widthFactor: 0.85),
              SizedBox(height: NoWaveSpacing.xs),
              NoWaveSkeletonLine(widthFactor: 0.4),
            ],
          ),
        ),
      ],
    );
  }
}
