import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:belog/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class SavedBlogsPage extends StatefulWidget {
  const SavedBlogsPage({super.key});

  @override
  State<SavedBlogsPage> createState() => _SavedBlogsPageState();
}

class _SavedBlogsPageState extends State<SavedBlogsPage>
    with WidgetsBindingObserver, RouteAware {
  List<Blog> _lastBlogs = []; // Store the last successful blog list

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchSavedBlogs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      savedRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    savedRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchSavedBlogs();
    }
  }

  @override
  void didPopNext() {
    // The viewer above this page owns its own like state; refresh so likes
    // toggled there are reflected in the saved list.
    _fetchSavedBlogs();
  }

  void _fetchSavedBlogs() {
    final appUserState = context.read<AppUserCubit>().state;
    if (appUserState is AppUserLoggedIn) {
      context.read<BlogLikedBloc>().add(
        UserLikedBlogs(userId: appUserState.user.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('我的收藏'),
        elevation: 1.0,
      ),
      body: BlocConsumer<BlogLikedBloc, BlogLikedState>(
        listener: (context, state) {
          if (state is UserLikedBlogsFailure) {
            showSnackBar(context, state.error);
          }
        },
        builder: (context, state) {
          if (state is UserLikedBlogsSuccess) {
            _lastBlogs = state.blogs;
          }

          if (state is UserLikedBlogsLoading) {
            return const Loader();
          } else if (state is UserLikedBlogsSuccess || _lastBlogs.isNotEmpty) {
            final blogsToShow = state is UserLikedBlogsSuccess
                ? state.blogs
                : _lastBlogs;
            if (blogsToShow.isEmpty) {
              return const Center(
                child: Text(
                  '你还没有收藏文章',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                _fetchSavedBlogs();
                await context.read<BlogLikedBloc>().stream.firstWhere(
                  (newState) =>
                      newState is UserLikedBlogsSuccess ||
                      newState is UserLikedBlogsFailure,
                );
              },
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16.0,
                  mainAxisSpacing: 16.0,
                  childAspectRatio: 0.75,
                ),
                itemCount: blogsToShow.length,
                itemBuilder: (context, index) {
                  final blog = blogsToShow[index];
                  return BlogGridItem(
                    blog: blog,
                    onTap: () {
                      context.push('/saved/view/${blog.id}', extra: blog);
                    },
                  );
                },
              ),
            );
          } else if (state is UserLikedBlogsFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载错误: ${state.error}'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _fetchSavedBlogs,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          return _lastBlogs.isEmpty
              ? const Loader()
              : RefreshIndicator(
                  onRefresh: () async {
                    _fetchSavedBlogs();
                    await context.read<BlogLikedBloc>().stream.firstWhere(
                      (newState) =>
                          newState is UserLikedBlogsSuccess ||
                          newState is UserLikedBlogsFailure,
                    );
                  },
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 16.0,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: _lastBlogs.length,
                    itemBuilder: (context, index) {
                      final blog = _lastBlogs[index];
                      return BlogGridItem(
                        blog: blog,
                        onTap: () {
                          context.push('/saved/view/${blog.id}', extra: blog);
                        },
                      );
                    },
                  ),
                );
        },
      ),
    );
  }
}
