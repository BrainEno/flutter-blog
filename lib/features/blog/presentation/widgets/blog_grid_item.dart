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
  final columns = width >= 900
      ? 4
      : width >= 600
      ? 3
      : 2;
  final tileWidth = (width - 16 * (columns - 1)) / columns;
  final scaler = MediaQuery.textScalerOf(context);
  final bodyScale = scaler.scale(14) / 14;
  final titleScale = scaler.scale(19) / 19;
  final scale = bodyScale > titleScale ? bodyScale : titleScale;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
    mainAxisExtent: tileWidth * 3 / 4 + 180 * (scale < 1 ? 1 : scale),
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
    final scheme = Theme.of(context).colorScheme;
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
                  aspectRatio: 4 / 3,
                ),
                if (blog.isDraft || editionLabel != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (blog.isDraft)
                          _TileBadge(
                            label: context.l10n.myArticlesDraftBadge,
                            background: scheme.secondaryContainer,
                            foreground: scheme.onSecondaryContainer,
                          ),
                        if (blog.isDraft && editionLabel != null)
                          const SizedBox(height: 4),
                        if (editionLabel != null)
                          _TileBadge(
                            label: editionLabel!,
                            background: scheme.surfaceContainerHighest,
                            foreground: scheme.onSurfaceVariant,
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
            const SizedBox(height: 8),
            Text(
              blog.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NoWaveTypography.title(context, size: 19),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NoWaveTypography.meta(context),
              ),
            ],
            const SizedBox(height: 6),
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

/// A small label laid over the cover: draft state, language edition.
class _TileBadge extends StatelessWidget {
  const _TileBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
