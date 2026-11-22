import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/article_tag_label.dart';
import 'package:flutter/material.dart';

/// A presentational article item. Navigation is deliberately supplied by the
/// caller so the same item works in feed, search, author and related lists.
class BlogCard extends StatelessWidget {
  const BlogCard({
    super.key,
    required this.blog,
    required this.onTap,
    this.featured = false,
    this.index,
    this.labelAuthor = false,
    this.onTagTap,
    this.quiet = false,
    this.ruled = true,
  });

  /// Whether a plain row draws its top rule. Off for the first row under a
  /// line the page already draws (a tab bar's hairline, a search field's
  /// underline), where a second rule a few points lower read as a double.
  final bool ruled;

  /// A row without its rule or its tags: for a short list laid on a surface
  /// (related reading), where the space between rows is enough.
  final bool quiet;

  final Blog blog;
  final VoidCallback onTap;
  final bool featured;
  final int? index;
  final bool labelAuthor;

  /// Opens a tag's article list. Kept as a callback so the item stays
  /// presentational and the page owns routing (see README).
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final author = authorDisplayName(l10n, blog.posterName);
    final authorLabel = labelAuthor ? l10n.posterLabel(author) : author;
    return NoWavePressable(
      onTap: onTap,
      child: featured
          ? _featured(context, authorLabel)
          : _row(context, authorLabel),
    );
  }

  Widget _metadata(BuildContext context, {int? ordinal}) {
    return Wrap(
      spacing: NoWaveSpacing.small,
      runSpacing: NoWaveSpacing.small,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // The running number opens the kicker line instead of standing in a
        // column of its own: centred on the same line as the tags (which
        // carry 48pt targets) rather than pinned above them, and the title
        // keeps the gutter the lead story's title starts on.
        // An extra step after it, so the number reads as the row's label
        // rather than as one more tag.
        if (ordinal != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.small),
            child: Text(
              formatNumber(
                Localizations.localeOf(context),
                ordinal,
              ).padLeft(2, '0'),
              style: NoWaveTypography.meta(context).copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        // A quiet row is a pointer to the next piece: its date, title and
        // author say enough, and a row of tags would only be noise.
        if (!quiet)
          for (final tag in blog.tags)
            // Words, not boxed chips: the same kicker the article opens
            // on, so a tag looks the same in the list and in the piece.
            ArticleTagLabel(
              tag: tag,
              quiet: true,
              onTap: onTagTap == null ? null : () => onTagTap!(tag),
            ),
        Text(
          formatDate(Localizations.localeOf(context), blog.updatedAt),
          style: NoWaveTypography.meta(context),
        ),
      ],
    );
  }

  Widget _featured(BuildContext context, String author) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArticleCover(
            title: blog.title,
            imageUrl: blog.imageUrl,
            seed: blog.id,
          ),
          const SizedBox(height: NoWaveSpacing.medium),
          _metadata(context),
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            blog.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: NoWaveTypography.title(context, size: 30),
          ),
          const SizedBox(height: NoWaveSpacing.small),
          _byline(context, author),
        ],
      ),
    );
  }

  /// The author, with the arrow at the end of the same line: the lead story
  /// and every row after it finish the same way.
  Widget _byline(BuildContext context, String author) {
    return Row(
      children: [
        Expanded(child: Text(author, style: NoWaveTypography.meta(context))),
        const SizedBox(width: NoWaveSpacing.small),
        const NoWavePressArrow(),
      ],
    );
  }

  Widget _row(BuildContext context, String author) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: quiet || !ruled
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: foreground.withAlpha(130))),
            ),
      padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metadata(context, ordinal: index),
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            blog.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NoWaveTypography.title(context, size: 24),
          ),
          const SizedBox(height: NoWaveSpacing.xs),
          _byline(context, author),
        ],
      ),
    );
  }
}
