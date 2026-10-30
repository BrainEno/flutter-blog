import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/utils/cover_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Shows a single article.
///
/// The page is opened from cards with the already fetched article passed as
/// `extra`, and from deep links (or a restored process) with only [blogId];
/// [BlogViewerCubit] loads the article in that case. Like state lives in a
/// page-scoped [BlogLikedBloc] created with this route.
class BlogViewerPage extends StatefulWidget {
  final String blogId;
  const BlogViewerPage({super.key, required this.blogId});

  @override
  State<BlogViewerPage> createState() => _BlogViewerPageState();
}

class _BlogViewerPageState extends State<BlogViewerPage> {
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
          }
        }
      },
      builder: (context, state) {
        if (state is BlogViewerLoaded) {
          return _ViewerScaffold(
            blog: state.blog,
            onRequestLogin: _requestLogin,
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
  const _ViewerScaffold({required this.blog, this.onRequestLogin});

  final Blog blog;
  final VoidCallback? onRequestLogin;

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
                  Row(
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
                  const SizedBox(height: 24),
                  Text(
                    blog.content,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
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
