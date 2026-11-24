import 'package:belog/core/design/components/no_wave_end_mark.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/category_navigation.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controls.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_sheet.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:belog/router/route_paths.dart';

/// The scrolling article: header, read-aloud controls, body, related articles
/// and comments.
///
/// A draft is the author's preview: a note under the header says so, and the
/// end matter - related reading and comments, both public conversation - is
/// left out until the piece is published.
///
/// Navigation targets are computed here from the current location, so the
/// caller only supplies data and the reader objects it already owns.
class ViewerArticleBody extends StatelessWidget {
  const ViewerArticleBody({
    super.key,
    required this.blog,
    required this.document,
    required this.reader,
    required this.blockKeys,
    required this.scrollController,
    required this.getRelatedArticles,
    required this.onRequestLogin,
    this.titleKey,
    this.controlsKey,
    this.endKey,
    this.headingKeys,
    this.textFactor = 1,
    this.onEditDraft,
  });

  final Blog blog;

  /// Parsed reading document; independent of whether speech is available.
  final ReadAloudDocument? document;

  /// Reader controller, null when this platform has no speech backend.
  final ReadAloudController? reader;

  /// One key per spoken block, empty when read-aloud is unavailable.
  final List<GlobalKey> blockKeys;

  final ScrollController scrollController;
  final GetRelatedArticles? getRelatedArticles;
  final VoidCallback onRequestLogin;

  /// Marks the title when read-aloud has not already keyed it, so the
  /// running head can tell when it has scrolled away.
  final GlobalKey? titleKey;

  /// Marks the full read-aloud controls, so the page can dock a compact
  /// player once they have scrolled away.
  final GlobalKey? controlsKey;

  /// Marks the end of the text, so the page can measure how far into the
  /// article - not into the comments under it - the reader is.
  final GlobalKey? endKey;

  /// Marks the body's headings, for the contents list.
  final Map<md.Node, GlobalKey>? headingKeys;

  /// How much larger than standard the reader has set the text.
  final double textFactor;

  /// Opens a draft in the editor; null leaves the draft note without the
  /// button (not the author, or a body only the web editor can carry).
  final VoidCallback? onEditDraft;

  @override
  Widget build(BuildContext context) {
    void openAuthor(String userId) {
      context.push(
        shellBranchLocation(
          GoRouterState.of(context).uri,
          RoutePaths.author(userId),
        ),
      );
    }

    final endMatter = Theme.of(context).colorScheme.surfaceContainer;
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: NoWaveSizes.contentColumn,
              ),
              child: Padding(
                // No top inset: the cover meets the app bar and runs to
                // the screen's edges; the header adds its own space when an
                // article has no cover.
                padding: const EdgeInsets.fromLTRB(
                  NoWaveSpacing.page,
                  0,
                  NoWaveSpacing.page,
                  NoWaveSpacing.section,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ArticleReaderHeader(
                      blog: blog,
                      onAuthorTap: () => openAuthor(blog.posterId),
                      onTagTap: (tag) => openTagArticles(context, tag),
                      onCategoryTap: (category) =>
                          openCategoryArticles(context, category),
                      titleHighlight: reader?.highlights.first,
                      titleKey: blockKeys.isEmpty ? titleKey : blockKeys.first,
                    ),
                    const SizedBox(height: NoWaveSpacing.section),
                    if (blog.isDraft) ...[
                      NoWaveNotice(
                        key: const ValueKey('reader-draft-notice'),
                        icon: Icons.visibility_outlined,
                        message: context.l10n.readerDraftPreviewNotice,
                        actionLabel: onEditDraft == null
                            ? null
                            : context.l10n.readerDraftEdit,
                        onAction: onEditDraft,
                      ),
                      const SizedBox(height: NoWaveSpacing.large),
                    ],
                    if (blog.document?.supported == false) ...[
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: NoWaveSpacing.medium,
                          ),
                          child: Text(
                            context.l10n.articleUnsupportedDocument,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ),
                    ],
                    if (reader != null)
                      KeyedSubtree(
                        key: controlsKey,
                        child: ReadAloudControls(controller: reader!),
                      ),
                    // Only the text follows the reader's size: the title,
                    // byline and controls above it keep the app's scale.
                    ReaderTextScale(
                      factor: textFactor,
                      child: MarkdownBody(
                        markdown: blog.content,
                        readAloudDocument: document,
                        readAloudController: reader,
                        readAloudBlockKeys: blockKeys,
                        headingKeys: headingKeys,
                        bodyStyle: NoWaveTypography.title(
                          context,
                          size: NoWaveTypeScale.articleBody,
                        ).copyWith(fontWeight: FontWeight.w400, height: 1.9),
                        headingStyle: NoWaveTypography.title(context),
                      ),
                    ),
                    const SizedBox(height: NoWaveSpacing.section),
                    // Just "The end": the author is introduced at the top of
                    // the piece, and naming them again here read as a
                    // repeat. No rules either side - the change of paper
                    // below is the break.
                    KeyedSubtree(
                      key: endKey,
                      child: NoWaveEndMark(
                        label: context.l10n.articleEnd,
                        ruled: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The end matter - related reading, then comments - is set on its
        // own sheet of the darker paper, edge to edge. One change of tone
        // says "the article is over" more plainly than any rule, and lets
        // the sections inside it drop theirs. A draft has none: nobody else
        // can read it yet, so there is nothing to relate or reply to.
        if (!blog.isDraft) ...[
          SliverToBoxAdapter(
            child: ColoredBox(
              key: const ValueKey('article-end-matter'),
              color: endMatter,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: NoWaveSizes.contentColumn,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NoWaveSpacing.page,
                      NoWaveSpacing.section,
                      NoWaveSpacing.page,
                      NoWaveSpacing.section,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (getRelatedArticles case final related?)
                          RelatedArticlesSection(
                            getRelatedArticles: related,
                            slug: blog.id,
                            onOpenArticle: (article) => context.push(
                              shellBranchLocation(
                                GoRouterState.of(context).uri,
                                RoutePaths.view(article.id),
                              ),
                              extra: article,
                            ),
                          ),
                        CommentsSection(
                          slug: blog.id,
                          onRequestLogin: onRequestLogin,
                          onOpenAuthor: openAuthor,
                          articleAuthorId: blog.posterId,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // A short thread still ends on the sheet, not on a strip of paper.
          SliverFillRemaining(
            hasScrollBody: false,
            child: ColoredBox(color: endMatter),
          ),
        ],
      ],
    );
  }
}
