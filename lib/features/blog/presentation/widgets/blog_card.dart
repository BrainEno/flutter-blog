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
  });

  final Blog blog;
  final VoidCallback onTap;
  final bool featured;
  final int? index;
  final bool labelAuthor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final author = blog.posterName?.trim().isNotEmpty == true
        ? blog.posterName!
        : l10n.anonymousAuthor;
    final authorLabel = labelAuthor ? l10n.posterLabel(author) : author;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        focusColor: AppPalette.orange.withAlpha(55),
        hoverColor: AppPalette.orange.withAlpha(25),
        child: featured
            ? _featured(context, authorLabel)
            : _row(context, authorLabel),
      ),
    );
  }

  Widget _metadata(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in blog.tags) ArticleTagLabel(tag: tag),
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
          ArticleCover(title: blog.title, imageUrl: blog.imageUrl),
          const SizedBox(height: NoWaveSpacing.medium),
          _metadata(context),
          const SizedBox(height: 10),
          Text(
            blog.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: NoWaveTypography.title(context, size: 30),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(author, style: NoWaveTypography.meta(context)),
              ),
              const SizedBox(width: 12),
              const ExcludeSemantics(
                child: Icon(Icons.arrow_forward, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String author) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: foreground.withAlpha(130))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (index != null) ...[
            SizedBox(
              width: 36,
              child: Text(
                formatNumber(
                  Localizations.localeOf(context),
                  index!,
                ).padLeft(2, '0'),
                style: NoWaveTypography.meta(context),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metadata(context),
                const SizedBox(height: 8),
                Text(
                  blog.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NoWaveTypography.title(context, size: 24),
                ),
                const SizedBox(height: 6),
                Text(author, style: NoWaveTypography.meta(context)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const ExcludeSemantics(child: Icon(Icons.arrow_forward, size: 20)),
        ],
      ),
    );
  }
}
