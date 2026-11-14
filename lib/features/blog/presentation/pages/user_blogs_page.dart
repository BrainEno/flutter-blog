import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_authoring_key.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:belog/features/blog/presentation/editor/structured_recovery_catalog_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_editor_page.dart';
import 'package:get_it/get_it.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class UserBlogsPage extends StatefulWidget {
  const UserBlogsPage({super.key, this.structuredOpener, this.recoveryList});

  /// Override only for tests; production uses the shared backend/session.
  final OpenStructuredEditingSession? structuredOpener;
  final ListStructuredRecoveries? recoveryList;

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
  bool _structuredOpen = false;

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
    if (blog.document != null) {
      if (_structuredOpen) return;
      final opener =
          widget.structuredOpener ?? GetIt.I<OpenStructuredEditingSession>();
      final userCubit = context.read<AppUserCubit>();
      final user = userCubit.state;
      final key = user is AppUserLoggedIn
          ? structuredAuthoringKey(
              blog: blog,
              signedInUserId: user.user.id,
              identity: opener.identity,
            )
          : null;
      if (key == null) {
        showSnackBar(context, context.l10n.structuredMissingIdentity);
        return;
      }
      final fence = NowaveSessionFence(
        userId: key.userId,
        generation: opener.identity.sessionGeneration,
      );
      final identity = _AuthoringIdentity(
        inner: opener.identity,
        user: userCubit,
        fence: fence,
        routeCurrent: () => mounted,
      );
      final session = LocalStructuredSession(
        key: key,
        fence: fence,
        opener: OpenStructuredEditingSession(
          reader: opener.reader,
          store: opener.store,
          identity: identity,
        ),
      );
      _structuredOpen = true;
      try {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => StructuredLocalEditorPage(session: session),
          ),
        );
      } finally {
        _structuredOpen = false;
        await identity.close();
      }
      // Local changes were not published and do not change the server list.
      return;
    }
    // The ordinary Markdown path and its publish safeguards stay unchanged.
    final changed = await context.push<bool>('/profile/editor', extra: blog);
    if (changed == true && mounted) {
      _fetchUserBlogs();
    }
  }

  Future<void> _openLocalRecoveries() async {
    if (_structuredOpen) return;
    final opener =
        widget.structuredOpener ?? GetIt.I<OpenStructuredEditingSession>();
    final list = widget.recoveryList ?? GetIt.I<ListStructuredRecoveries>();
    final user = context.read<AppUserCubit>();
    final state = user.state;
    if (state is! AppUserLoggedIn ||
        state.user.id != opener.identity.activeUserId ||
        !(opener.identity.accessToken?.isNotEmpty ?? false) ||
        !identical(list.identity, opener.identity)) {
      showSnackBar(context, context.l10n.structuredMissingIdentity);
      return;
    }
    final fence = NowaveSessionFence(
      userId: state.user.id,
      generation: opener.identity.sessionGeneration,
    );
    _structuredOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StructuredRecoveryCatalogPage(
            list: list,
            opener: opener,
            user: user,
            fence: fence,
          ),
        ),
      );
    } finally {
      _structuredOpen = false;
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
            tooltip: context.l10n.structuredCatalogTitle,
            icon: const Icon(Icons.offline_bolt_outlined),
            onPressed: _openLocalRecoveries,
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
            padding: const EdgeInsets.all(NoWaveSpacing.page),
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

/// Immediately fences private editor state on either UI-account or network
/// session changes. Once invalidated, switching back cannot resurrect it.
class _AuthoringIdentity implements NowaveSessionIdentity {
  _AuthoringIdentity({
    required this.inner,
    required this.user,
    required this.fence,
    required this.routeCurrent,
  }) {
    user.identityRevision.addListener(_changed);
    _subscription = inner.identityChanges.listen((_) => _changed());
  }
  final NowaveSessionIdentity inner;
  final AppUserCubit user;
  final NowaveSessionFence fence;
  final bool Function() routeCurrent;
  final _events = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<void> _subscription;
  bool _invalid = false;

  bool get _active {
    final current = user.state;
    if (!routeCurrent() ||
        current is! AppUserLoggedIn ||
        current.user.id != fence.userId ||
        inner.activeUserId != fence.userId ||
        inner.sessionGeneration != fence.generation ||
        (inner.accessToken?.isEmpty ?? true)) {
      _invalid = true;
    }
    return !_invalid;
  }

  void _changed() {
    if (!_active) _invalid = true;
    if (!_events.isClosed) _events.add(null);
  }

  @override
  String? get activeUserId => _active ? inner.activeUserId : null;
  @override
  String? get accessToken => _active ? inner.accessToken : null;
  @override
  int get sessionGeneration => inner.sessionGeneration;
  @override
  Stream<void> get identityChanges => _events.stream;

  Future<void> close() async {
    user.identityRevision.removeListener(_changed);
    await _subscription.cancel();
    await _events.close();
  }
}
