import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/bog_upload/bloc/blog_upload_bloc.dart';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除文章'),
        content: Text('确定删除「${blog.title}」吗？删除后可在回收站中恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
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
        title: const Text('我的文章'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '回收站',
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
                showSnackBar(context, state.error);
              }
            },
          ),
          BlocListener<BlogUploadBloc, BlogUploadState>(
            listener: (context, state) {
              if (state is BlogDeleteSuccess) {
                showSnackBar(context, '已删除，可在回收站中恢复');
                _fetchUserBlogs();
              } else if (state is BlogUploadFailure) {
                showSnackBar(context, state.error);
              }
            },
          ),
        ],
        child: BlocBuilder<BlogByBloc, BlogByState>(
          builder: (context, state) {
            if (state is GetBlogsByUserLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is GetBlogsByUserSuccess) {
              final blogs = state.blogs;
              if (blogs.isEmpty) {
                return const Center(child: Text('您还没有发布任何文章'));
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: 0.75,
                  ),
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
            return const Center(child: Text('无法加载文章'));
          },
        ),
      ),
    );
  }
}
