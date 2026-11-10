import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// The shapes of a feed's cards, for the frame before the articles arrive.
///
/// The feed used to show a centred sentence while it loaded, and the list then
/// appeared above it: the heading, a cover the height of a third of the screen
/// and a title. The skeleton borrows that rhythm - a wide cover, two title
/// lines, a meta line, then rows separated by hairlines - so the page does not
/// reflow when the data lands.
///
/// It contains no text of its own: the whole placeholder is decorative and the
/// wrapper announces [semanticLabel] once (see [NoWaveSkeleton]).
class BlogFeedSkeleton extends StatelessWidget {
  const BlogFeedSkeleton({
    super.key,
    this.rows = 4,
    this.semanticLabel,
    this.showFeatured = true,
  });

  /// How many compact rows to show.
  final int rows;

  /// Whether this list has the feed's featured first card.
  final bool showFeatured;

  /// What a screen reader hears once, in place of the shapes.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return NoWaveSkeleton(
      semanticLabel: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showFeatured) const _FeaturedCardSkeleton(),
          for (var row = 0; row < rows; row++) const _CompactRowSkeleton(),
        ],
      ),
    );
  }
}

/// The first article: cover, metadata, a two-line title and the author.
class _FeaturedCardSkeleton extends StatelessWidget {
  const _FeaturedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: NoWaveSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: NoWaveSizes.coverAspectWide,
            child: NoWaveSkeletonBlock(),
          ),
          SizedBox(height: NoWaveSpacing.medium),
          NoWaveSkeletonLine(widthFactor: 0.4),
          SizedBox(height: NoWaveSpacing.small),
          NoWaveSkeletonLine(widthFactor: 0.95),
          SizedBox(height: NoWaveSpacing.xs),
          NoWaveSkeletonLine(widthFactor: 0.55),
          SizedBox(height: NoWaveSpacing.small),
          NoWaveSkeletonLine(widthFactor: 0.25),
        ],
      ),
    );
  }
}

/// Every later article: a rule, a metadata line, a two-line title, the author.
/// No cover and no thumbnail - the compact feed row has neither.
class _CompactRowSkeleton extends StatelessWidget {
  const _CompactRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        NoWaveSkeletonDivider(),
        Padding(
          padding: EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              NoWaveSkeletonLine(widthFactor: 0.3),
              SizedBox(height: NoWaveSpacing.small),
              NoWaveSkeletonLine(widthFactor: 0.85),
              SizedBox(height: NoWaveSpacing.xs),
              NoWaveSkeletonLine(widthFactor: 0.2),
            ],
          ),
        ),
      ],
    );
  }
}
