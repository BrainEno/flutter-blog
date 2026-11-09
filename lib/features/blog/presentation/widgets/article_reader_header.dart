import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_highlight.dart';
import 'package:belog/features/blog/presentation/widgets/article_category_label.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/article_tag_label.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Article identity and author details, independent of routing and state.
class ArticleReaderHeader extends StatelessWidget {
  const ArticleReaderHeader({
    super.key,
    required this.blog,
    required this.onAuthorTap,
    this.onTagTap,
    this.onCategoryTap,
    this.titleHighlight,
    this.titleKey,
  });

  final Blog blog;
  final VoidCallback onAuthorTap;

  /// Opens a tag's article list; null keeps the labels read-only.
  final ValueChanged<String>? onTagTap;

  /// Opens a category's article list; null keeps those plates read-only.
  final ValueChanged<CategoryRef>? onCategoryTap;
  final ValueListenable<ReadAloudHighlight?>? titleHighlight;
  final GlobalKey? titleKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = authorDisplayName(l10n, blog.posterName);
    final scheme = Theme.of(context).colorScheme;
    // Only what can be both named and opened. A cache row written before the
    // names were kept carries ids alone; drawing a chip for it would offer a
    // destination with no address.
    final categories = [
      for (final category in blog.categories)
        if (category.slug.isNotEmpty && category.name.isNotEmpty) category,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (categories.isNotEmpty) ...[
          Wrap(
            spacing: NoWaveSpacing.small,
            runSpacing: NoWaveSpacing.small,
            children: [
              for (final category in categories)
                ArticleCategoryLabel(
                  category: category,
                  onTap: onCategoryTap == null
                      ? null
                      : () => onCategoryTap!(category),
                ),
            ],
          ),
          const SizedBox(height: NoWaveSpacing.medium),
        ],
        if (blog.tags.isNotEmpty) ...[
          Wrap(
            spacing: NoWaveSpacing.small,
            runSpacing: NoWaveSpacing.small,
            children: [
              for (final tag in blog.tags)
                ArticleTagLabel(
                  tag: tag,
                  onTap: onTagTap == null ? null : () => onTagTap!(tag),
                ),
            ],
          ),
          const SizedBox(height: NoWaveSpacing.medium),
        ],
        KeyedSubtree(
          key: titleKey,
          child: Semantics(
            header: true,
            child: titleHighlight == null
                ? Text(
                    blog.title,
                    style: NoWaveTypography.title(context, size: 36),
                  )
                : ValueListenableBuilder<ReadAloudHighlight?>(
                    valueListenable: titleHighlight!,
                    builder: (context, highlight, child) => Text.rich(
                      readAloudTextSpan(
                        text: blog.title,
                        range: SpeechTextRange(0, blog.title.length),
                        highlight: highlight,
                      ),
                      style: NoWaveTypography.title(context, size: 36),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: NoWaveSpacing.large),
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
                padding: const EdgeInsets.symmetric(
                  vertical: NoWaveSpacing.medium,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoWaveAvatar(
                      name: name,
                      imageUrl: blog.posterAvatar ?? '',
                      size: 48,
                    ),
                    const SizedBox(width: NoWaveSpacing.small),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: NoWaveSpacing.xs),
                          Wrap(
                            spacing: NoWaveSpacing.small,
                            runSpacing: NoWaveSpacing.xs,
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
                    const SizedBox(width: NoWaveSpacing.small),
                    const ExcludeSemantics(
                      child: Icon(Icons.arrow_forward, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Structured image blocks render in their original body positions.
        // Avoid repeating the first one as an invented cover.
        if (blog.document?.supported != true ||
            blog.document?.hasImages != true) ...[
          const SizedBox(height: NoWaveSpacing.small),
          ArticleCover(
            title: blog.title,
            imageUrl: blog.imageUrl,
            seed: blog.id,
          ),
        ],
      ],
    );
  }
}
