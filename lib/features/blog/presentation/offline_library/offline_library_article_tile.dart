import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A text-only Offline Library row.
///
/// It intentionally does not render the article cover or avatar. A cached
/// article body does not guarantee that remote images are in the image cache,
/// and creating an image provider while browsing a supposedly local library
/// could start a network request. The normal viewer keeps its established image
/// behaviour after a reader explicitly opens an article.
class OfflineLibraryArticleTile extends StatelessWidget {
  const OfflineLibraryArticleTile.catalog({
    super.key,
    required this.entry,
    required this.index,
    required this.onTap,
  }) : result = null;

  OfflineLibraryArticleTile.search({
    super.key,
    required OfflineLibrarySearchResult this.result,
    required this.index,
    required this.onTap,
  }) : entry = result.entry;

  /// Width of the two-digit editorial index column. It is intentionally wider
  /// than a spacing token so list numbers line up with article text.
  static const double _indexWidth = 36;

  final OfflineLibraryEntry entry;
  final OfflineLibrarySearchResult? result;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final article = entry.article;
    final matches = result;
    final l10n = context.l10n;
    final author = authorDisplayName(l10n, article.posterName);
    final theme = Theme.of(context);
    final border = theme.colorScheme.onSurface.withAlpha(100);
    final matchDescription = matches == null
        ? null
        : l10n.offlineLibraryMatches(_matchFields(l10n, matches.fields));

    return Semantics(
      container: true,
      button: true,
      label: l10n.offlineLibraryOpenArticle(article.title),
      hint: matchDescription,
      onTap: onTap,
      // The visual InkWell would otherwise merge its title/tag children into
      // this node. One named action is shorter and more useful to a reader
      // using a screen reader than an unlabelled row followed by its text.
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            focusColor: AppPalette.orange.withAlpha(55),
            hoverColor: AppPalette.orange.withAlpha(25),
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: border)),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: NoWaveSpacing.medium,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: SizedBox(
                      width: _indexWidth,
                      child: Text(
                        formatNumber(
                          Localizations.localeOf(context),
                          index,
                        ).padLeft(2, '0'),
                        style: NoWaveTypography.meta(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: NoWaveSpacing.small),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: NoWaveSpacing.small,
                          runSpacing: NoWaveSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatDate(
                                Localizations.localeOf(context),
                                article.updatedAt,
                              ),
                              style: NoWaveTypography.meta(context),
                            ),
                            for (final tag in article.tags.take(4))
                              _TagText(label: tag),
                          ],
                        ),
                        const SizedBox(height: NoWaveSpacing.small),
                        Text(
                          article.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: NoWaveTypography.title(context, size: 24),
                        ),
                        const SizedBox(height: NoWaveSpacing.xs),
                        Text(author, style: NoWaveTypography.meta(context)),
                        if (matchDescription != null) ...[
                          const SizedBox(height: NoWaveSpacing.small),
                          Text(
                            matchDescription,
                            style: NoWaveTypography.meta(context).copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (matches?.hasBodyExcerpt ?? false) ...[
                          const SizedBox(height: NoWaveSpacing.small),
                          Text(
                            l10n.offlineLibraryBodyExcerpt,
                            style: NoWaveTypography.meta(context),
                          ),
                          const SizedBox(height: NoWaveSpacing.xs),
                          Text(
                            matches!.bodyExcerpt!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
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
    );
  }

  String _matchFields(
    AppLocalizations l10n,
    Set<OfflineLibraryMatchField> fields,
  ) {
    final labels = <String>[
      if (fields.contains(OfflineLibraryMatchField.title))
        l10n.offlineLibraryMatchTitle,
      if (fields.contains(OfflineLibraryMatchField.author))
        l10n.offlineLibraryMatchAuthor,
      if (fields.contains(OfflineLibraryMatchField.tag))
        l10n.offlineLibraryMatchTags,
      if (fields.contains(OfflineLibraryMatchField.body))
        l10n.offlineLibraryMatchBody,
    ];
    return labels.join(', ');
  }
}

/// A non-interactive cache metadata tag. Tapping a tag here must not launch an
/// online tag query: Offline Library promises not to make network requests.
class _TagText extends StatelessWidget {
  const _TagText({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NoWaveSpacing.small,
        vertical: NoWaveSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: foreground.withAlpha(130)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: NoWaveTypography.meta(context).copyWith(color: foreground),
      ),
    );
  }
}
