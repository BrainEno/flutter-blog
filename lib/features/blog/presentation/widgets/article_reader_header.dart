import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/design/design_tokens.dart';
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
import 'package:flutter/rendering.dart' show OverflowBoxFit;

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
    this.bleed = NoWaveSpacing.page,
  });

  /// How far the cover reaches past the text column on each side - the page
  /// gutter, so the picture runs to the screen's edges on a phone.
  final double bleed;

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
    final quiet = NoWaveTypography.meta(
      context,
    ).copyWith(color: scheme.onSurfaceVariant);
    final titleStyle = NoWaveTypography.title(
      context,
      size: NoWaveTypeScale.articleTitle,
    ).copyWith(height: 1.15);
    // Structured image blocks render in their original body positions.
    // Avoid repeating the first one as an invented cover.
    final showCover =
        blog.document?.supported != true || blog.document?.hasImages != true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The piece opens on its picture, edge to edge, the way a magazine
        // feature does; type follows on the paper below it. No rules: the
        // picture, the size of the title and the space between them carry
        // the order.
        if (showCover) ...[
          _Bleed(
            gutter: bleed,
            child: ArticleCover(
              title: blog.title,
              imageUrl: blog.imageUrl,
              seed: blog.id,
            ),
          ),
          const SizedBox(height: NoWaveSpacing.medium),
        ] else
          const SizedBox(height: NoWaveSpacing.medium),
        // The kicker: what kind of piece this is, in one quiet line.
        if (categories.isNotEmpty || blog.tags.isNotEmpty) ...[
          Wrap(
            // Each word sits in a 48pt target that is already wider than
            // a short word, so the gap between them stays small.
            spacing: NoWaveSpacing.small,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final category in categories)
                ArticleCategoryLabel(
                  category: category,
                  quiet: true,
                  onTap: onCategoryTap == null
                      ? null
                      : () => onCategoryTap!(category),
                ),
              for (final tag in blog.tags)
                ArticleTagLabel(
                  tag: tag,
                  quiet: true,
                  onTap: onTagTap == null ? null : () => onTagTap!(tag),
                ),
            ],
          ),
          // The kicker's words sit in 48pt targets, which already put
          // air between them and the title.
          const SizedBox(height: NoWaveSpacing.xs),
        ],
        KeyedSubtree(
          key: titleKey,
          child: Semantics(
            header: true,
            child: titleHighlight == null
                ? Text(blog.title, style: titleStyle)
                : ValueListenableBuilder<ReadAloudHighlight?>(
                    valueListenable: titleHighlight!,
                    builder: (context, highlight, child) => Text.rich(
                      readAloudTextSpan(
                        text: blog.title,
                        range: SpeechTextRange(0, blog.title.length),
                        highlight: highlight,
                      ),
                      style: titleStyle,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: NoWaveSpacing.medium),
        // The byline: who, and when. The whole line opens the author.
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
                  vertical: NoWaveSpacing.small,
                ),
                child: Row(
                  children: [
                    NoWaveAvatar(
                      name: name,
                      imageUrl: blog.posterAvatar ?? '',
                      size: NoWaveSizes.bylineAvatar,
                    ),
                    const SizedBox(width: NoWaveSpacing.medium),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: NoWaveTypography.meta(context).copyWith(
                              fontSize: NoWaveTypeScale.label,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          Wrap(
                            spacing: NoWaveSpacing.small,
                            children: [
                              Text(
                                formatDate(
                                  Localizations.localeOf(context),
                                  blog.updatedAt,
                                ),
                                style: quiet,
                              ),
                              ExcludeSemantics(child: Text('·', style: quiet)),
                              Text(
                                calculateReadingTime(l10n, blog.content),
                                style: quiet,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lets [child] run [gutter] past the column on both sides, while taking
/// only the column's width in the layout.
class _Bleed extends StatelessWidget {
  const _Bleed({required this.gutter, required this.child});

  final double gutter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth + 2 * gutter;
        return OverflowBox(
          minWidth: width,
          maxWidth: width,
          fit: OverflowBoxFit.deferToChild,
          child: child,
        );
      },
    );
  }
}
