import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
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
            showSnackBar(context, state.error);
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
                  child: const Icon(CupertinoIcons.add),
                )
              : const SizedBox();
        },
      ),
    );
  }

  Widget _buildBody(BlogState state) {
    final blogs = _visibleBlogs(state);

    // Initial load with nothing to show yet.
    if (blogs.isEmpty &&
        (state is BlogInitial || state is BlogFirstPageLoading)) {
      return const Loader();
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
                state.error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _fetchFirstPage,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }

    // Loaded but empty: distinguishable from loading and from failure.
    if (blogs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: Text('还没有文章，下拉刷新试试')),
        ],
      );
    }

    final loadingMore =
        state is BlogLoaded && state.isLoadingMore && !state.hasReachedMax;
    final reachedMax = state is BlogLoaded && state.hasReachedMax;
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 30),
      itemCount: blogs.length + (loadingMore || reachedMax ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == blogs.length) {
          if (loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: Text('没有更多了', style: TextStyle(color: Colors.grey)),
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
    if (state is BlogListFailure && state.previousState is BlogLoaded) {
      return (state.previousState as BlogLoaded).blogs;
    }
    return const [];
  }
}
