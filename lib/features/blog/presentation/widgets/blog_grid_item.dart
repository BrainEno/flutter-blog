import 'package:belog/core/design/components/no_wave_badge.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/extract_description.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:flutter/material.dart';

/// Size the cover and text independently so wider screens and large system
/// fonts do not overflow a fixed-height tile.
SliverGridDelegateWithFixedCrossAxisCount blogGridDelegate(
  BuildContext context,
) {
  final width = MediaQuery.sizeOf(context).width;
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
    final description = extractDescription(blog.content);
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
                if (onLongPress != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filled(
                      tooltip: context.l10n.deleteArticleTitle,
                      onPressed: onLongPress,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NoWaveSpacing.small),
            Text(
              blog.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NoWaveTypography.title(context, size: 19),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: NoWaveSpacing.xs),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NoWaveTypography.meta(context),
              ),
            ],
            const SizedBox(height: NoWaveSpacing.xs),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NoWaveTypography.meta(context),
            ),
            Text(
              formatDate(Localizations.localeOf(context), blog.updatedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NoWaveTypography.meta(context),
            ),
          ],
        ),
      ),
    );
  }
}
