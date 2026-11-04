import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_highlight.dart';
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
    this.titleHighlight,
    this.titleKey,
  });

  final Blog blog;
  final VoidCallback onAuthorTap;

  /// Opens a tag's article list; null keeps the labels read-only.
  final ValueChanged<String>? onTagTap;
  final ValueListenable<ReadAloudHighlight?>? titleHighlight;
  final GlobalKey? titleKey;

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
            children: [
              for (final tag in blog.tags)
                ArticleTagLabel(
                  tag: tag,
                  onTap: onTagTap == null ? null : () => onTagTap!(tag),
                ),
            ],
          ),
          const SizedBox(height: 16),
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
        // Structured image blocks render in their original body positions.
        // Avoid repeating the first one as an invented cover.
        if (blog.document?.supported != true ||
            blog.document?.hasImages != true) ...[
          const SizedBox(height: 8),
          ArticleCover(title: blog.title, imageUrl: blog.imageUrl),
        ],
      ],
    );
  }
}
