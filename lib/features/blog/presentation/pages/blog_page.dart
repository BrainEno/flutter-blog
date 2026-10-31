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
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
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
    _fetchFirstPage();
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
    if (state == AppLifecycleState.resumed) _fetchFirstPage();
  }

  void _fetchFirstPage() {
    context.read<BlogBloc>().add(const BlogFetchFirstPage());
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
    return Scaffold(
      appBar: AppBar(title: const NoWaveMasthead()),
      body: BlocConsumer<BlogBloc, BlogState>(
        listener: (context, state) {
          if (state is BlogListFailure) {
            showSnackBar(
              context,
              localizedFailure(context.l10n, state.failure),
            );
          }
        },
        builder: (context, state) => RefreshIndicator(
          onRefresh: _refreshBlogs,
          child: _buildBody(state),
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
    );
  }

  Widget _heading() => NoWaveSectionHeading(
    title: context.l10n.feedHeading,
    companion: context.l10n.feedHeadingCompanion,
    eyebrow: context.l10n.feedEyebrow,
  );

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );

  Widget _statusList(Widget status) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(
      NoWaveSpacing.page,
      24,
      NoWaveSpacing.page,
      NoWaveSpacing.section,
    ),
    children: [
      _contentWidth(_heading()),
      const SizedBox(height: 56),
      _contentWidth(status),
    ],
  );

  Widget _buildBody(BlogState state) {
    final l10n = context.l10n;
    final blogs = _visibleBlogs(state);
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
      );
    }
    if (blogs.isEmpty) {
      return _statusList(NoWaveStatus(message: l10n.feedEmpty));
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
              child: _heading(),
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
                l10n.feedNoMore,
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
            onTap: () => context.push('/view/${blog.id}', extra: blog),
          ),
        );
      },
    );
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
