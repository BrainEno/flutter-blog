import 'package:belog/core/design/components/no_wave_badge.dart';
import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/reader/article_excerpt.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/reading_mark.dart';
import 'package:flutter/material.dart';

/// Size the cover and text independently so wider screens and large system
/// fonts do not overflow a fixed-height tile.
SliverGridDelegateWithFixedCrossAxisCount blogGridDelegate(
  BuildContext context, {
  double gutter = 0,
}) {
  // The tiles share what is left between the page's gutters; measuring the
  // whole screen made every tile taller than its cover and text needed.
  final width = MediaQuery.sizeOf(context).width - 2 * gutter;
  final columns = NoWaveBreakpoints.columnsFor(width);
  final gap = NoWaveSpacing.medium;
  final tileWidth = (width - gap * (columns - 1)) / columns;
  final scaler = MediaQuery.textScalerOf(context);
  final bodyScale = scaler.scale(14) / 14;
  final titleScale = scaler.scale(19) / 19;
  final scale = bodyScale > titleScale ? bodyScale : titleScale;
  // Cover at its token aspect ratio, plus room for title and metadata that
  // grows with the reader's text size instead of clipping.
  final coverHeight = tileWidth / NoWaveSizes.coverAspect;
  final textHeight = 180 * (scale < 1 ? 1 : scale);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: gap,
    mainAxisSpacing: gap,
    mainAxisExtent: coverHeight + textHeight,
  );
}

class BlogGridItem extends StatelessWidget {
  const BlogGridItem({
    super.key,
    required this.blog,
    required this.onTap,
    this.onLongPress,
    this.editionLabel,
  });

  final Blog blog;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Language edition label, shown next to the draft badge.
  ///
  /// Only the cross-language "my articles" view needs it: everywhere else the
  /// list is one language by construction, and a badge on every tile would be
  /// noise. Null renders no badge.
  final String? editionLabel;

  @override
  Widget build(BuildContext context) {
    final name = authorDisplayName(context.l10n, blog.posterName);
    final description = articleExcerpt(blog);
    return NoWavePressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ArticleCover(
                title: blog.title,
                imageUrl: blog.imageUrl,
                seed: blog.id,
                aspectRatio: NoWaveSizes.coverAspect,
              ),
              if (blog.isDraft || editionLabel != null)
                Positioned(
                  top: NoWaveSpacing.small,
                  left: NoWaveSpacing.small,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (blog.isDraft)
                        NoWaveBadge(label: context.l10n.myArticlesDraftBadge),
                      if (blog.isDraft && editionLabel != null)
                        const SizedBox(height: NoWaveSpacing.xs),
                      if (editionLabel != null)
                        NoWaveBadge(
                          label: editionLabel!,
                          tone: NoWaveBadgeTone.neutral,
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            blog.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(context),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: NoWaveSpacing.xs),
            // Every tile in a row has the same height, sized for a title on
            // two lines. A one-line title gives that line to the excerpt
            // instead of leaving a gap under the date.
            LayoutBuilder(
              builder: (context, constraints) => Text(
                description,
                maxLines: _titleLines(context, constraints.maxWidth) > 1
                    ? 2
                    : 3,
                overflow: TextOverflow.ellipsis,
                style: NoWaveTypography.meta(context),
              ),
            ),
          ],
          const SizedBox(height: NoWaveSpacing.xs),
          // Delete waits at the end of the byline as a plain glyph. It used
          // to be a filled red disc on every cover - the loudest thing on
          // the page was the one action nobody comes here to take.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NoWaveTypography.meta(context),
                    ),
                    // How far the reader got rides on the date's line, so
                    // every tile in a row keeps the same height.
                    ReadingMarkBuilder(
                      blogId: blog.id,
                      builder: (context, mark) {
                        final date = formatDate(
                          Localizations.localeOf(context),
                          blog.updatedAt,
                        );
                        return Text(
                          mark == null ? date : '$date · $mark',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NoWaveTypography.meta(context),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (onLongPress != null)
                IconButton(
                  tooltip: context.l10n.deleteArticleTitle,
                  onPressed: onLongPress,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: NoWaveIconSize.row,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _titleStyle(BuildContext context) =>
      NoWaveTypography.title(context, size: 19);

  /// How many lines the title sets in at [width], up to its two.
  int _titleLines(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(text: blog.title, style: _titleStyle(context)),
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines;
  }
}
