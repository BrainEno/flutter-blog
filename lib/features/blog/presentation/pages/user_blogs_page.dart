import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
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
  /// Whether the list is read across every language edition.
  ///
  /// Off by default: the single-language list is one row per work, which is
  /// what most readers of their own archive expect. Turning it on is how an
  /// author finds the `en` or legacy `zh-TW` edition they meant to edit.
  bool _allEditions = false;

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
      // `/me/articles` instead of the public author list: a restored or
      // demoted work is a server-side draft and would otherwise be invisible
      // here, with no way to publish it again.
      final userId = appUserState.user.id;
      context.read<BlogByBloc>().add(
        _allEditions
            ? GetMyArticleEditionsEvent(userId: userId)
            : GetMyArticlesEvent(userId: userId),
      );
    }
  }

  void _toggleEditions() {
    setState(() => _allEditions = !_allEditions);
    _fetchUserBlogs();
  }

  Future<void> _editBlog(Blog blog) async {
    // The editor pops with `true` when the article was changed; refresh the
    // list only in that case.
    final changed = await context.push<bool>('/profile/editor', extra: blog);
    if (changed == true && mounted) {
      _fetchUserBlogs();
    }
  }

  Future<void> _openRecycleBin() async {
    await context.push('/profile/my-articles/recycle-bin');
    if (mounted) _fetchUserBlogs();
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
            tooltip: _allEditions
                ? context.l10n.myArticlesSingleLocale
                : context.l10n.myArticlesAllLocales,
            isSelected: _allEditions,
            icon: const Icon(Icons.translate),
            onPressed: _toggleEditions,
          ),
          IconButton(
            tooltip: context.l10n.recycleBinTooltip,
            icon: const Icon(Icons.delete_outline),
            onPressed: _openRecycleBin,
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
                // The remote delete committed even though cache cleanup failed.
                if (state.failure.code == 'article.deletedCacheFailed') {
                  _fetchUserBlogs();
                }
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
            } else if (state is GetMyArticleEditionsSuccess) {
              return _buildList(
                state.blogs,
                editions: state.editions,
              );
            } else if (state is GetBlogsByUserSuccess) {
              return _buildList(state.blogs);
            }
            if (state is GetBlogsByUserFailure) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: NoWaveStatus(
                    message: localizedFailure(context.l10n, state.failure),
                    actionLabel: context.l10n.actionRetry,
                    onAction: _fetchUserBlogs,
                  ),
                ),
              );
            }
            return Center(child: Text(context.l10n.myArticlesLoadFailed));
          },
        ),
      ),
    );
  }

  /// The archive itself: one tile per row, with an edition badge when the
  /// list spans languages.
  ///
  /// [editions] is null for the single-language read. When it is present but
  /// unconfirmed (`locales == null`) the deployment ignored `allLocales`, so
  /// the list is the current language only and the header says exactly that
  /// instead of implying the archive is complete.
  Widget _buildList(List<Blog> blogs, {ArticleEditions? editions}) {
    final l10n = context.l10n;
    if (blogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NoWaveStatus(message: l10n.noArticlesYet),
        ),
      );
    }
    final hasDrafts = blogs.any((blog) => blog.isDraft);
    final editionHint = editions == null
        ? null
        : editions.isConfirmed
        ? l10n.myArticlesEditionsHint
        : l10n.myArticlesEditionsUnavailable;
    return RefreshIndicator(
      onRefresh: () async {
        _fetchUserBlogs();
        await context.read<BlogByBloc>().stream.firstWhere(
          (newState) =>
              newState is GetBlogsByUserSuccess ||
              newState is GetMyArticleEditionsSuccess ||
              newState is GetBlogsByUserFailure,
        );
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (hasDrafts)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  l10n.myArticlesDraftsHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (editionHint != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  editionHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.builder(
              gridDelegate: blogGridDelegate(context),
              itemCount: blogs.length,
              itemBuilder: (context, index) {
                final blog = blogs[index];
                return BlogGridItem(
                  blog: blog,
                  editionLabel: editions == null
                      ? null
                      : contentEditionLabel(l10n, blog.locale),
                  onTap: () => _editBlog(blog),
                  onLongPress: () => _confirmDelete(blog),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
