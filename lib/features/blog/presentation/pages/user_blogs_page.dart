import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class UserBlogsPage extends StatefulWidget {
  const UserBlogsPage({super.key});

  @override
  State<UserBlogsPage> createState() => _UserBlogsPageState();
}

class _UserBlogsPageState extends State<UserBlogsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserBlogs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchUserBlogs();
    }
  }

  void _fetchUserBlogs() {
    final appUserState = context.read<AppUserCubit>().state;
    if (appUserState is AppUserLoggedIn) {
      context.read<BlogByBloc>().add(
        GetBlogByPosterEvent(userId: appUserState.user.id),
      );
    }
  }

  Future<void> _editBlog(Blog blog) async {
    // The editor pops with `true` when the article was changed; refresh the
    // list only in that case.
    final changed = await context.push<bool>('/profile/editor', extra: blog);
    if (changed == true && mounted) {
      _fetchUserBlogs();
    }
  }

  /// Long-press delete: the article moves to the recycle bin, where it can
  /// still be restored until the server purge.
  Future<void> _confirmDelete(Blog blog) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteArticleTitle),
        content: Text(l10n.deleteArticleBody(blog.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<BlogUploadBloc>().add(DeleteBlogEvent(blogId: blog.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myArticlesTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: context.l10n.recycleBinTooltip,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => context.push('/profile/recycle-bin'),
          ),
        ],
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<BlogByBloc, BlogByState>(
            listener: (context, state) {
              if (state is GetBlogsByUserFailure) {
                showSnackBar(
                  context,
                  localizedFailure(context.l10n, state.failure),
                );
              }
            },
          ),
          BlocListener<BlogUploadBloc, BlogUploadState>(
            listener: (context, state) {
              if (state is BlogDeleteSuccess) {
                showSnackBar(context, context.l10n.articleDeletedNotice);
                _fetchUserBlogs();
              } else if (state is BlogUploadFailure) {
                showSnackBar(
                  context,
                  localizedFailure(context.l10n, state.failure),
                );
              }
            },
          ),
        ],
        child: BlocBuilder<BlogByBloc, BlogByState>(
          builder: (context, state) {
            if (state is GetBlogsByUserLoading) {
              return Center(
                child: CircularProgressIndicator(
                  semanticsLabel: context.l10n.loadingArticles,
                ),
              );
            } else if (state is GetBlogsByUserSuccess) {
              final blogs = state.blogs;
              if (blogs.isEmpty) {
                return Center(child: Text(context.l10n.noArticlesYet));
              }
              return RefreshIndicator(
                onRefresh: () async {
                  _fetchUserBlogs();
                  await context.read<BlogByBloc>().stream.firstWhere(
                    (newState) =>
                        newState is GetBlogsByUserSuccess ||
                        newState is GetBlogsByUserFailure,
                  );
                },
                child: GridView.builder(
                  gridDelegate: blogGridDelegate(context),
                  itemCount: blogs.length,
                  itemBuilder: (context, index) {
                    final blog = blogs[index];
                    return BlogGridItem(
                      blog: blog,
                      onTap: () => _editBlog(blog),
                      onLongPress: () => _confirmDelete(blog),
                    );
                  },
                ),
              );
            }
            if (state is GetBlogsByUserFailure) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(localizedFailure(context.l10n, state.failure)),
                    TextButton(
                      onPressed: _fetchUserBlogs,
                      child: Text(context.l10n.actionRetry),
                    ),
                  ],
                ),
              );
            }
            return Center(child: Text(context.l10n.myArticlesLoadFailed));
          },
        ),
      ),
    );
  }
}
