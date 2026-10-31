import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/article_share.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// Shows a single article.
///
/// The page is opened from cards with the already fetched article passed as
/// `extra`, and from deep links (or a restored process) with only [blogId];
/// [BlogViewerCubit] loads the article in that case. Like state lives in a
/// page-scoped [BlogLikedBloc] created with this route.
class BlogViewerPage extends StatefulWidget {
  final String blogId;

  /// Device-local reading history sink (issue #22); injectable for tests,
  /// resolved from the service locator when absent.
  final ReadingHistoryStore? historyStore;

  /// Related-articles rider loader (issue #19); same injection pattern.
  final GetRelatedArticles? getRelatedArticles;
  const BlogViewerPage({
    super.key,
    required this.blogId,
    this.historyStore,
    this.getRelatedArticles,
  });

  @override
  State<BlogViewerPage> createState() => _BlogViewerPageState();
}

class _BlogViewerPageState extends State<BlogViewerPage> {
  /// Guards the history write so retries and like refreshes do not spam
  /// the store (the upsert would deduplicate anyway, but skip for free).
  String? _historyRecordedFor;

  @override
  void initState() {
    super.initState();
    _checkIfIsLiked();
  }

  void _checkIfIsLiked() {
    final appUserState = context.read<AppUserCubit>().state;

    if (appUserState is AppUserLoggedIn) {
      context.read<BlogLikedBloc>().add(
        GetIsBlogLiked(userId: appUserState.user.id, blogId: widget.blogId),
      );
    }
  }

  /// Reading history is device-local and per account (issue #22): only
  /// signed-in users are recorded, failures are swallowed (the reader must
  /// never break because a bookkeeping write failed).
  Future<void> _recordReadingHistory(String userId, Blog blog) async {
    if (_historyRecordedFor == '${userId}_${blog.id}') return;
    _historyRecordedFor = '${userId}_${blog.id}';
    try {
      final store =
          widget.historyStore ?? GetIt.instance<ReadingHistoryStore>();
      await store.record(userId: userId, blog: blog);
    } catch (e, stackTrace) {
      AppLogger.error(
        'recording the reading history failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _requestLogin() {
    final currentLocation = GoRouterState.of(context).uri.toString();
    context.push('/login?redirect=${Uri.encodeComponent(currentLocation)}');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BlogViewerCubit, BlogViewerState>(
      listener: (context, state) {
        if (state is BlogViewerFailure) {
          showSnackBar(context, localizedFailure(context.l10n, state.failure));
        } else if (state is BlogViewerLoaded) {
          final appUserState = context.read<AppUserCubit>().state;
          if (appUserState is AppUserLoggedIn) {
            context.read<BlogLikedBloc>().add(
              GetIsBlogLiked(
                userId: appUserState.user.id,
                blogId: state.blog.id,
              ),
            );
            _recordReadingHistory(appUserState.user.id, state.blog);
          }
        }
      },
      builder: (context, state) {
        if (state is BlogViewerLoaded) {
          return _ViewerScaffold(
            blog: state.blog,
            onRequestLogin: _requestLogin,
            getRelatedArticles:
                widget.getRelatedArticles ??
                GetIt.instance<GetRelatedArticles>(),
          );
        }
        if (state is BlogViewerFailure) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(localizedFailure(context.l10n, state.failure)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        context.read<BlogViewerCubit>().load(widget.blogId),
                    child: Text(context.l10n.actionRetry),
                  ),
                ],
              ),
            ),
          );
        }
        return const Scaffold(body: Loader());
      },
    );
  }
}

class _ViewerScaffold extends StatelessWidget {
  const _ViewerScaffold({
    required this.blog,
    required this.onRequestLogin,
    required this.getRelatedArticles,
  });

  final Blog blog;
  final VoidCallback onRequestLogin;
  final GetRelatedArticles getRelatedArticles;

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

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Only share a canonical URL when WEB_BASE_URL is configured.
          if (articleWebUrl(blog.id) != null)
            IconButton(
              tooltip: context.l10n.shareArticleTooltip,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareArticle(title: blog.title, slug: blog.id),
            ),
          BlocConsumer<BlogLikedBloc, BlogLikedState>(
            listener: (context, state) {
              if (state is ToggleBlogLikeFailure) {
                showSnackBar(
                  context,
                  localizedFailure(context.l10n, state.failure),
                );
              }
            },
            builder: (context, state) {
              final isSaved = state.likedBlogs[blog.id] ?? false;
              return IconButton(
                tooltip: isSaved
                    ? context.l10n.unsaveTooltip
                    : context.l10n.saveTooltip,
                icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () {
                  final userState = context.read<AppUserCubit>().state;
                  if (userState is AppUserLoggedIn) {
                    context.read<BlogLikedBloc>().add(
                      ToggleBlogLike(
                        userId: userState.user.id,
                        blogId: blog.id,
                      ),
                    );
                  } else {
                    showSnackBar(context, context.l10n.signInRequired);
                    onRequestLogin();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: CustomScrollView(
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
                      ),
                      const SizedBox(height: 32),
                      MarkdownBody(
                        markdown: blog.content,
                        bodyStyle: NoWaveTypography.title(
                          context,
                          size: 18,
                        ).copyWith(fontWeight: FontWeight.w400, height: 1.9),
                        headingStyle: NoWaveTypography.title(context),
                      ),
                      const SizedBox(height: 30),
                      RelatedArticlesSection(
                        getRelatedArticles: getRelatedArticles,
                        slug: blog.id,
                        onOpenArticle: (related) => context.push(
                          shellBranchLocation(
                            GoRouterState.of(context).uri,
                            '/view/${Uri.encodeComponent(related.id)}',
                          ),
                          extra: related,
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
      ),
    );
  }
}
