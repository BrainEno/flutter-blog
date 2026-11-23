import 'package:belog/core/design/components/no_wave_refresh.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_skeleton.dart';
import 'package:belog/features/blog/presentation/widgets/my_article_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

/// The author's own archive: every article and server draft, the way into the
/// editor for a new piece (the write button) or an existing one (a tap), and
/// each article's actions (the row's "more" button or a long press): edit,
/// publish a draft or take a public article back to one, and deletion into
/// the recycle bin.
class UserBlogsPage extends StatefulWidget {
  const UserBlogsPage({super.key, this.sessionIdentity});

  /// The session a publish or draft change is fenced to; null uses the app's.
  final NowaveSessionIdentity? sessionIdentity;

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

  /// The article whose visibility is being changed, and the change: true
  /// publishes, false takes it back to a draft. One at a time.
  String? _visibilityBlogId;
  bool _visibilityPublishes = true;

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

  /// Opens an article in the editor. Every body the editor can carry without
  /// losing anything opens there - plain text and structured documents alike;
  /// anything richer (a quote with an attribution, say) is only editable on
  /// the web, and the author is told so instead of losing it on save.
  Future<void> _editBlog(Blog blog) async {
    if (blog.editableBody == null) {
      showSnackBar(context, context.l10n.articleNotEditableInApp);
      return;
    }
    await _openEditor(blog);
  }

  /// The editor answers `true` after a publish, so the list re-reads only
  /// when something on the server changed.
  Future<void> _openEditor([Blog? blog]) async {
    final changed = await context.push<bool>(
      RoutePaths.profileEditor,
      extra: blog,
    );
    if (changed == true && mounted) {
      _fetchUserBlogs();
    }
  }

  Future<void> _openRecycleBin() async {
    await context.push(RoutePaths.recycleBin);
    if (mounted) _fetchUserBlogs();
  }

  /// The row's actions. Tapping the row still opens the editor directly.
  Future<void> _showActions(Blog blog) async {
    if (_visibilityBlogId != null) return;
    final action = await MyArticleActionsSheet.show(
      context,
      blog: blog,
      visibilityBlock: _visibilityBlockOf(blog),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case MyArticleAction.edit:
        await _editBlog(blog);
      case MyArticleAction.publish:
        _changeVisibility(blog, publish: true);
      case MyArticleAction.unpublish:
        await _confirmUnpublish(blog);
      case MyArticleAction.delete:
        await _confirmDelete(blog);
    }
  }

  /// A change of visibility resends the article exactly as the editor would
  /// after opening it and saving without an edit, so it needs the same two
  /// things the editor needs: a body it can carry and the revision to
  /// condition the write on.
  static MyArticleVisibilityBlock? _visibilityBlockOf(Blog blog) {
    final body = blog.editableBody;
    if (body == null) return MyArticleVisibilityBlock.webOnly;
    // A row without its body (an abridged list answer) must never be sent
    // back as the article: that would replace the text with nothing.
    if (blog.authoringRevision == null || body.markdown.trim().isEmpty) {
      return MyArticleVisibilityBlock.refreshFirst;
    }
    return null;
  }

  /// Taking a public article back to a draft hides it from readers, so it
  /// asks first - the same question the editor asks.
  Future<void> _confirmUnpublish(Blog blog) async {
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.editorUnpublishTitle,
      message: l10n.editorUnpublishBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.editorUnpublishConfirm,
    );
    if (!confirmed || !mounted) return;
    _changeVisibility(blog, publish: false);
  }

  /// Publishes a draft, or takes a public article back to one, without
  /// opening the editor.
  ///
  /// no-wave has no separate publish switch: the change is the article's own
  /// title, body, tags and edition sent back with `publish` flipped. The
  /// write is conditioned on the revision this row was read at, so an
  /// article changed elsewhere since is a conflict, never an overwrite; the
  /// repository also re-reads the article and refuses a body the app cannot
  /// carry. Cover, categories and summary are left as the server has them.
  void _changeVisibility(Blog blog, {required bool publish}) {
    final body = blog.editableBody;
    final revision = blog.authoringRevision;
    final userState = context.read<AppUserCubit>().state;
    if (_visibilityBlockOf(blog) != null ||
        body == null ||
        revision == null ||
        userState is! AppUserLoggedIn) {
      return;
    }
    final session =
        widget.sessionIdentity ?? GetIt.instance<NowaveSessionManager>();
    setState(() {
      _visibilityBlogId = blog.id;
      _visibilityPublishes = publish;
    });
    context.read<BlogUploadBloc>().add(
      UpdateBlogEvent(
        blogId: blog.id,
        expectedRevision: revision,
        title: blog.title.trim(),
        content: body.markdown.trim(),
        tags: List<String>.unmodifiable(blog.tags),
        sessionFence: NowaveSessionFence(
          userId: userState.user.id,
          generation: session.sessionGeneration,
        ),
        // The edition this row is, not the language the app is shown in.
        locale: blog.locale,
        publish: publish,
      ),
    );
  }

  void _onVisibilityState(BuildContext context, BlogUploadState state) {
    final publishes = _visibilityPublishes;
    setState(() => _visibilityBlogId = null);
    if (state is BlogUploadSuccess) {
      showSnackBar(
        context,
        publishes
            ? context.l10n.myArticlePublished
            : context.l10n.myArticleUnpublished,
      );
    } else if (state is BlogUploadVersionConflict) {
      showSnackBar(context, context.l10n.myArticleVisibilityConflict);
    } else if (state is BlogUploadFailure) {
      showSnackBar(context, localizedFailure(context.l10n, state.failure));
    }
    // Every outcome re-reads: the badge must say what the server now holds.
    _fetchUserBlogs();
  }

  /// Delete, from the row's actions: the article moves to the recycle bin,
  /// where it can still be restored until the server purge.
  Future<void> _confirmDelete(Blog blog) async {
    final l10n = context.l10n;
    // The shared dialog owns the destructive styling and the "dismissed means
    // no" rule; this screen only supplies the wording.
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.deleteArticleTitle,
      message: l10n.deleteArticleBody(blog.title),
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.actionDelete,
    );
    if (!confirmed || !mounted) return;
    context.read<BlogUploadBloc>().add(DeleteBlogEvent(blogId: blog.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myArticlesTitle),
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('my-articles-write'),
        onPressed: _openEditor,
        icon: const Icon(Icons.edit_outlined),
        label: Text(context.l10n.editorNewTitle),
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
              if (_visibilityBlogId != null &&
                  (state is BlogUploadSuccess || state is BlogUploadFailure)) {
                _onVisibilityState(context, state);
              } else if (state is BlogDeleteSuccess) {
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
              // The real archive is a sliver grid inside a page-padded
              // viewport; the skeleton borrows the same delegate and padding.
              return BlogGridSkeleton(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                semanticLabel: context.l10n.loadingArticles,
              );
            } else if (state is GetMyArticleEditionsSuccess) {
              return _buildList(state.blogs, editions: state.editions);
            } else if (state is GetBlogsByUserSuccess) {
              return _buildList(state.blogs);
            }
            if (state is GetBlogsByUserFailure) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(NoWaveSpacing.medium),
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
          padding: const EdgeInsets.all(NoWaveSpacing.page),
          child: NoWaveStatus(message: l10n.noArticlesYet),
        ),
      );
    }
    final hasDrafts = blogs.any((blog) => blog.isDraft);
    final editionsConfirmed = editions?.isConfirmed ?? false;
    final String? editionHint;
    if (editions == null) {
      editionHint = null;
    } else if (editionsConfirmed) {
      editionHint = l10n.myArticlesEditionsHint;
    } else {
      editionHint = l10n.myArticlesEditionsUnavailable;
    }
    return NoWaveRefresh(
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
                padding: const EdgeInsets.fromLTRB(
                  NoWaveSpacing.page,
                  NoWaveSpacing.page,
                  NoWaveSpacing.page,
                  0,
                ),
                child: NoWaveNotice(message: l10n.myArticlesDraftsHint),
              ),
            ),
          if (editionHint != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  NoWaveSpacing.page,
                  NoWaveSpacing.page,
                  NoWaveSpacing.page,
                  0,
                ),
                child: NoWaveNotice(
                  message: editionHint,
                  // An older deployment is a limit the reader has to know
                  // about, not a failure.
                  tone: editionsConfirmed
                      ? NoWaveNoticeTone.info
                      : NoWaveNoticeTone.warning,
                ),
              ),
            ),
          SliverPadding(
            // Room under the last row for the write button floating over it.
            padding: const EdgeInsets.fromLTRB(
              NoWaveSpacing.page,
              NoWaveSpacing.page,
              NoWaveSpacing.page,
              NoWaveSpacing.page + NoWaveSizes.tapTarget + NoWaveSpacing.large,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: blogGridDelegate(
                context,
                gutter: NoWaveSpacing.page,
              ),
              itemCount: blogs.length,
              itemBuilder: (context, index) {
                final blog = blogs[index];
                return BlogGridItem(
                  blog: blog,
                  editionLabel: editions == null
                      ? null
                      : contentEditionLabel(l10n, blog.locale),
                  onTap: () => _editBlog(blog),
                  onLongPress: () => _showActions(blog),
                  onActions: () => _showActions(blog),
                  busy: _visibilityBlogId == blog.id,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
