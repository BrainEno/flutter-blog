import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controls.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The scrolling article: header, read-aloud controls, body, related articles
/// and comments.
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

  @override
  Widget build(BuildContext context) {
    void openAuthor(String userId) {
      context.push(
        shellBranchLocation(
          GoRouterState.of(context).uri,
          '/author/${Uri.encodeComponent(userId)}',
        ),
      );
    }

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  NoWaveSpacing.page,
                  16,
                  NoWaveSpacing.page,
                  40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ArticleReaderHeader(
                      blog: blog,
                      onAuthorTap: () => openAuthor(blog.posterId),
                      onTagTap: (tag) => openTagArticles(context, tag),
                      titleHighlight: reader?.highlights.first,
                      titleKey: blockKeys.isEmpty ? null : blockKeys.first,
                    ),
                    const SizedBox(height: NoWaveSpacing.section),
                    if (blog.document?.supported == false) ...[
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
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
                    if (reader != null) ReadAloudControls(controller: reader!),
                    MarkdownBody(
                      markdown: blog.content,
                      readAloudDocument: document,
                      readAloudController: reader,
                      readAloudBlockKeys: blockKeys,
                      bodyStyle: NoWaveTypography.title(
                        context,
                        size: 18,
                      ).copyWith(fontWeight: FontWeight.w400, height: 1.9),
                      headingStyle: NoWaveTypography.title(context),
                    ),
                    const SizedBox(height: 30),
                    if (getRelatedArticles case final related?)
                      RelatedArticlesSection(
                        getRelatedArticles: related,
                        slug: blog.id,
                        onOpenArticle: (article) => context.push(
                          shellBranchLocation(
                            GoRouterState.of(context).uri,
                            '/view/${Uri.encodeComponent(article.id)}',
                          ),
                          extra: article,
                        ),
                      ),
                    CommentsSection(
                      slug: blog.id,
                      onRequestLogin: onRequestLogin,
                      onOpenAuthor: openAuthor,
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
