import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/common/widgets/no_wave_masthead.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reconcileViewerAndRefresh();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reconcileViewerAndRefresh();
  }

  void _fetchFirstPage() {
    context.read<BlogBloc>().add(const BlogFetchFirstPage());
  }

  String? _viewerId(AppUserState state) =>
      state is AppUserLoggedIn ? state.user.id : null;

  void _reconcileViewerAndRefresh() {
    final bloc = context.read<BlogBloc>();
    final viewerId = _viewerId(context.read<AppUserCubit>().state);
    final current = bloc.state;
    // A page may be reattached after an account change happened elsewhere.
    // Listener callbacks only observe future changes, not the initial state.
    if (current.kind == BlogFeedKind.following &&
        current.viewerId != viewerId) {
      bloc.add(BlogViewerChanged(viewerId));
    } else {
      bloc.add(const BlogFetchFirstPage());
    }
  }

  void _selectFeed(BlogFeedKind kind, BlogState state) {
    final viewerId = _viewerId(context.read<AppUserCubit>().state);
    if (kind == state.kind &&
        (kind != BlogFeedKind.following || state.viewerId == viewerId)) {
      return;
    }
    if (kind == BlogFeedKind.following &&
        (viewerId == null || viewerId.isEmpty)) {
      showSnackBar(context, context.l10n.signInRequired);
      context.push('/login?redirect=${Uri.encodeComponent('/')}');
      return;
    }
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    context.read<BlogBloc>().add(
      BlogFetchFirstPage(
        kind: kind,
        viewerId: kind == BlogFeedKind.following ? viewerId : null,
      ),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<BlogBloc>().add(const BlogLoadMore());
    }
  }

  Future<void> _refreshBlogs() async {
    _fetchFirstPage();
    await context.read<BlogBloc>().stream.firstWhere(
      (state) => state is BlogLoaded || state is BlogListFailure,
    );
  }

  Future<void> _openEditor() async {
    final published = await context.push<bool>('/editor');
    if (published == true && mounted) _fetchFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    final viewerId = context.select<AppUserCubit, String?>(
      (cubit) => _viewerId(cubit.state),
    );
    return BlocListener<AppUserCubit, AppUserState>(
      listenWhen: (previous, current) =>
          _viewerId(previous) != _viewerId(current),
      listener: (context, state) =>
          context.read<BlogBloc>().add(BlogViewerChanged(_viewerId(state))),
      child: Scaffold(
        appBar: AppBar(title: const NoWaveMasthead()),
        body: BlocConsumer<BlogBloc, BlogState>(
          listener: (context, state) {
            if (state is BlogListFailure &&
                (state.kind != BlogFeedKind.following ||
                    state.viewerId == viewerId)) {
              showSnackBar(
                context,
                localizedFailure(context.l10n, state.failure),
              );
            }
          },
          builder: (context, state) => Column(
            children: [
              _feedSelector(state),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshBlogs,
                  child: _buildBody(state, viewerId),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: BlocSelector<AppUserCubit, AppUserState, bool>(
          selector: (state) => state is AppUserLoggedIn,
          builder: (context, isLoggedIn) => isLoggedIn
              ? FloatingActionButton(
                  onPressed: _openEditor,
                  tooltip: context.l10n.newPostTooltip,
                  child: const Icon(CupertinoIcons.add),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _feedSelector(BlogState state) {
    final l10n = context.l10n;
    return _contentWidth(
      Padding(
        padding: const EdgeInsets.fromLTRB(
          NoWaveSpacing.page,
          12,
          NoWaveSpacing.page,
          0,
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (kind, label) in [
              (BlogFeedKind.latest, l10n.feedTabLatest),
              (BlogFeedKind.featured, l10n.feedTabFeatured),
              (BlogFeedKind.popular, l10n.feedTabPopular),
              (BlogFeedKind.following, l10n.feedTabFollowing),
            ])
              ChoiceChip(
                label: Text(label),
                selected: state.kind == kind,
                onSelected: (_) => _selectFeed(kind, state),
              ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BlogFeedKind kind) {
    final l10n = context.l10n;
    final title = switch (kind) {
      BlogFeedKind.latest => l10n.feedHeading,
      BlogFeedKind.featured => l10n.feedTabFeatured,
      BlogFeedKind.popular => l10n.feedTabPopular,
      BlogFeedKind.following => l10n.feedTabFollowing,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoWaveSectionHeading(
          title: title,
          companion: kind == BlogFeedKind.latest
              ? l10n.feedHeadingCompanion
              : null,
          eyebrow: l10n.feedEyebrow,
        ),
        if (kind == BlogFeedKind.popular) ...[
          const SizedBox(height: 8),
          Text(
            l10n.feedPopularDescription,
            style: NoWaveTypography.meta(context),
          ),
        ],
      ],
    );
  }

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );

  Widget _statusList(Widget status, BlogFeedKind kind) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(
      NoWaveSpacing.page,
      24,
      NoWaveSpacing.page,
      NoWaveSpacing.section,
    ),
    children: [
      _contentWidth(_heading(kind)),
      const SizedBox(height: 56),
      _contentWidth(status),
    ],
  );

  Widget _buildBody(BlogState state, String? viewerId) {
    final l10n = context.l10n;
    // A session event can reach the UI before the queued bloc reset. Hide
    // the old viewer's follow list immediately, even for that brief frame.
    if (state.kind == BlogFeedKind.following &&
        (viewerId == null || viewerId != state.viewerId)) {
      return _statusList(
        NoWaveStatus(message: l10n.signInRequired),
        state.kind,
      );
    }
    final blogs = _visibleBlogs(state);
    final isCached = _visibleSource(state) == BlogFeedSource.cache;
    if (blogs.isEmpty &&
        (state is BlogInitial || state is BlogFirstPageLoading)) {
      return Loader(semanticLabel: l10n.loadingArticles);
    }
    if (state is BlogListFailure && blogs.isEmpty) {
      return _statusList(
        NoWaveStatus(
          message: localizedFailure(l10n, state.failure),
          actionLabel: l10n.actionRetry,
          onAction: _fetchFirstPage,
        ),
        state.kind,
      );
    }
    if (blogs.isEmpty) {
      final emptyMessage = switch (state.kind) {
        BlogFeedKind.latest => l10n.feedEmpty,
        BlogFeedKind.featured => l10n.feedFeaturedEmpty,
        BlogFeedKind.popular => l10n.feedPopularEmpty,
        BlogFeedKind.following => l10n.feedFollowingEmpty,
      };
      return _statusList(
        isCached
            ? NoWaveStatus(
                message: l10n.feedCachedEmpty,
                actionLabel: l10n.actionRetry,
                onAction: _fetchFirstPage,
              )
            : NoWaveStatus(message: emptyMessage),
        state.kind,
      );
    }

    final loadingMore =
        state is BlogLoaded && state.isLoadingMore && !state.hasReachedMax;
    final reachedMax = state is BlogLoaded && state.hasReachedMax;
    final failed = state is BlogListFailure;
    final hasFooter = loadingMore || reachedMax || failed;
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.page,
        24,
        NoWaveSpacing.page,
        NoWaveSpacing.section,
      ),
      itemCount: 1 + blogs.length + (hasFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _contentWidth(
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(state.kind),
                  if (isCached) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.feedCachedNotice,
                        style: NoWaveTypography.meta(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        final articleIndex = index - 1;
        if (articleIndex == blogs.length) {
          if (failed) {
            return Center(
              child: TextButton(
                onPressed: _fetchFirstPage,
                child: Text(l10n.actionRetry),
              ),
            );
          }
          if (loadingMore) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: l10n.loadingMoreArticles,
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                isCached ? l10n.feedCachedNoMore : l10n.feedNoMore,
                style: NoWaveTypography.meta(context),
              ),
            ),
          );
        }
        final blog = blogs[articleIndex];
        return _contentWidth(
          BlogCard(
            blog: blog,
            featured: articleIndex == 0,
            index: articleIndex + 1,
            onTagTap: (tag) => openTagArticles(context, tag),
            onTap: () => context.push('/view/${blog.id}', extra: blog),
          ),
        );
      },
    );
  }

  BlogFeedSource? _visibleSource(BlogState state) {
    if (state is BlogLoaded) return state.source;
    if (state is BlogFirstPageLoading) return state.previousSource;
    if (state is BlogListFailure && state.previousState != null) {
      return _visibleSource(state.previousState!);
    }
    return null;
  }

  List<Blog> _visibleBlogs(BlogState state) {
    if (state is BlogLoaded) return state.blogs;
    if (state is BlogFirstPageLoading) return state.previousBlogs;
    if (state is BlogListFailure && state.previousState != null) {
      return _visibleBlogs(state.previousState!);
    }
    return const [];
  }
}
