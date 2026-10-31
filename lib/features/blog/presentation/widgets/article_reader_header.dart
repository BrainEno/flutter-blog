import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/article_tag_label.dart';
import 'package:flutter/material.dart';

/// Article identity and author details, independent of routing and state.
class ArticleReaderHeader extends StatelessWidget {
  const ArticleReaderHeader({
    super.key,
    required this.blog,
    required this.onAuthorTap,
  });

  final Blog blog;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = blog.posterName?.trim().isNotEmpty == true
        ? blog.posterName!
        : l10n.anonymousAuthor;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blog.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final tag in blog.tags) ArticleTagLabel(tag: tag)],
          ),
          const SizedBox(height: 16),
        ],
        Semantics(
          header: true,
          child: Text(
            blog.title,
            style: NoWaveTypography.title(context, size: 36),
          ),
        ),
        const SizedBox(height: 24),
        Divider(height: 1, color: scheme.onSurface.withAlpha(130)),
        Semantics(
          button: true,
          label: l10n.authorPageSemantic(name),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAuthorTap,
              focusColor: AppPalette.orange.withAlpha(55),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoWaveAvatar(
                      name: name,
                      imageUrl: blog.posterAvatar ?? '',
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                formatDate(
                                  Localizations.localeOf(context),
                                  blog.updatedAt,
                                ),
                                style: NoWaveTypography.meta(context),
                              ),
                              Text(
                                calculateReadingTime(l10n, blog.content),
                                style: NoWaveTypography.meta(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ExcludeSemantics(
                      child: Icon(Icons.arrow_forward, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ArticleCover(title: blog.title, imageUrl: blog.imageUrl),
      ],
    );
  }
}
