import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/common/widgets/loader.dart';
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
    // One guarded refresh per resume; the bloc drops it while a newer
    // request is already in flight.
    if (state == AppLifecycleState.resumed) {
      _fetchFirstPage();
    }
  }

  void _fetchFirstPage() {
    context.read<BlogBloc>().add(const BlogFetchFirstPage());
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // The bloc ignores this while a request is running, once the end is
      // reached, or before a list exists.
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
    // The editor pops with `true` when something was published, so the feed
    // reloads page 1 instead of appending a stale page.
    final published = await context.push<bool>('/editor');
    if (published == true && mounted) {
      _fetchFirstPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ImageIcon(AssetImage('assets/images/icon.png'), size: 30),
            SizedBox(width: 7),
            const Text('Bottom Think'),
          ],
        ),
      ),
      body: BlocConsumer<BlogBloc, BlogState>(
        listener: (context, state) {
          if (state is BlogListFailure) {
            showSnackBar(
              context,
              localizedFailure(context.l10n, state.failure),
            );
          }
        },
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _refreshBlogs,
            child: _buildBody(state),
          );
        },
      ),
      floatingActionButton: BlocSelector<AppUserCubit, AppUserState, bool>(
        selector: (state) => state is AppUserLoggedIn,
        builder: (context, isLoggedIn) {
          return isLoggedIn
              ? FloatingActionButton(
                  onPressed: _openEditor,
                  tooltip: context.l10n.newPostTooltip,
                  child: const Icon(CupertinoIcons.add),
                )
              : const SizedBox();
        },
      ),
    );
  }

  Widget _buildBody(BlogState state) {
    final l10n = context.l10n;
    final blogs = _visibleBlogs(state);

    // Initial load with nothing to show yet.
    if (blogs.isEmpty &&
        (state is BlogInitial || state is BlogFirstPageLoading)) {
      return Loader(semanticLabel: l10n.loadingArticles);
    }

    // Actionable failure without any list to fall back to.
    if (state is BlogListFailure && blogs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                localizedFailure(l10n, state.failure),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _fetchFirstPage,
              child: Text(l10n.actionRetry),
            ),
          ),
        ],
      );
    }

    // Loaded but empty: distinguishable from loading and from failure.
    if (blogs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(child: Text(l10n.feedEmpty)),
        ],
      );
    }

    final loadingMore =
        state is BlogLoaded && state.isLoadingMore && !state.hasReachedMax;
    final reachedMax = state is BlogLoaded && state.hasReachedMax;
    final failed = state is BlogListFailure;
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 30),
      itemCount: blogs.length + (loadingMore || reachedMax || failed ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == blogs.length) {
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
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: l10n.loadingMoreArticles,
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                l10n.feedNoMore,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }
        return BlogCard(blog: blogs[index]);
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
