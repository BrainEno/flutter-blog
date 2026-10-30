import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/article_share.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/utils/cover_url.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
          showSnackBar(context, state.error);
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
                  Text(state.error),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        context.read<BlogViewerCubit>().load(widget.blogId),
                    child: const Text('重试'),
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
    this.onRequestLogin,
    this.getRelatedArticles,
  });

  final Blog blog;
  final VoidCallback? onRequestLogin;
  final GetRelatedArticles? getRelatedArticles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            floating: false,
            pinned: true,
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.all(16),
              centerTitle: true,
              title: Text(
                blog.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black87,
                      offset: Offset(1, 1),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    // Versioned, cache-busting URL shared with the feed
                    // card and editor (see cover_url.dart).
                    imageUrl: coverUrlOf(blog),
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha((0.3 * 255).toInt()),
                          Colors.black.withAlpha((0.7 * 255).toInt()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Share (issue #21): visible only when WEB_BASE_URL is
              // configured - a link that cannot open must never be
              // shared. Blog.id is the article's public slug. The
              // payload is title + canonical web URL only.
              if (articleWebUrl(blog.id) != null)
                IconButton(
                  tooltip: '分享文章',
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: () =>
                      shareArticle(title: blog.title, slug: blog.id),
                ),
              BlocConsumer<BlogLikedBloc, BlogLikedState>(
                listener: (context, state) {
                  if (state is ToggleBlogLikeFailure) {
                    showSnackBar(context, state.error);
                  }
                },
                builder: (context, state) {
                  // Use likedBlogs map to determine if the blog is saved
                  final isSaved = state.likedBlogs[blog.id] ?? false;
                  return IconButton(
                    tooltip: isSaved ? '取消收藏' : '收藏',
                    icon: Icon(
                      isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      final appUserState = context.read<AppUserCubit>().state;
                      if (appUserState is AppUserLoggedIn) {
                        context.read<BlogLikedBloc>().add(
                          ToggleBlogLike(
                            userId: appUserState.user.id,
                            blogId: blog.id,
                          ),
                        );
                      } else {
                        showSnackBar(context, '请先登录账户');
                        onRequestLogin?.call();
                      }
                    },
                  );
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The author row opens the public author page
                  // (issue #20); posterId is the stable user id the
                  // follow endpoints address.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/author/${blog.posterId}'),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: blog.posterAvatar != null
                              ? CachedNetworkImageProvider(blog.posterAvatar!)
                              : null,
                          child: blog.posterAvatar == null
                              ? const Icon(Icons.person, size: 20)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              blog.posterName?.isNotEmpty == true
                                  ? blog.posterName!
                                  : '匿名作者',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  formatDate(blog.updatedAt),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  calculateReadingTime(blog.content),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Markdown rendering (issue #17): plain-text articles
                  // render as paragraphs, so existing content stays
                  // readable. Links and images are http(s)-only.
                  MarkdownBody(markdown: blog.content),
                  const SizedBox(height: 30),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: blog.tags
                        .map(
                          (tag) => Chip(
                            label: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppPalette.gradient1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                            backgroundColor: Colors.grey.withAlpha(
                              (0.1 * 255).toInt(),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                  // Related-articles rider and the comment thread
                  // (issue #19). Comments live in the page-scoped
                  // CommentBloc created by the viewer route.
                  RelatedArticlesSection(
                    getRelatedArticles: getRelatedArticles!,
                    slug: blog.id,
                  ),
                  CommentsSection(
                    slug: blog.id,
                    onRequestLogin: onRequestLogin,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
