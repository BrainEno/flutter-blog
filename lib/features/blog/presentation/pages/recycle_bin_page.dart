import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The author's recycle bin: tombstones with their purge deadline and a
/// restore action. A restored article comes back as a draft and shows up
/// in "my articles" again.
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  @override
  void initState() {
    super.initState();
    context.read<RecycleBinBloc>().add(RecycleBinRequested());
  }

  /// Days left until the server sweep purges the tombstone for good.
  /// The retention window is server policy, so the deadline is taken
  /// from the API's `purgesAt` instead of being recomputed locally.
  String _purgeDeadlineText(DeletedBlog blog) {
    final purgesAt = blog.purgesAt;
    if (purgesAt == null) {
      return '超过保留期限后将被永久删除';
    }
    final days = purgesAt.difference(DateTime.now()).inDays + 1;
    if (days <= 0) {
      return '即将被永久删除';
    }
    return '$days 天后将被永久删除';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回收站'), centerTitle: true),
      body: BlocConsumer<RecycleBinBloc, RecycleBinState>(
        listener: (context, state) {
          if (state is RecycleBinRestoreFailure) {
            showSnackBar(context, state.message);
          } else if (state is RecycleBinSuccess) {
            final title = state.lastRestoredTitle;
            if (title != null) {
              showSnackBar(context, '「$title」已恢复为草稿，可在我的文章中查看');
            }
          }
        },
        builder: (context, state) {
          if (state is RecycleBinLoading || state is RecycleBinInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is RecycleBinFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.error),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => context.read<RecycleBinBloc>().add(
                      RecycleBinRequested(),
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final blogs = state is RecycleBinSuccess
              ? state.blogs
              : (state as RecycleBinRestoreFailure).blogs;
          final restoringArticleId = state is RecycleBinSuccess
              ? state.restoringArticleId
              : null;
          if (blogs.isEmpty) {
            return const Center(child: Text('回收站是空的'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              context.read<RecycleBinBloc>().add(RecycleBinRequested());
              await context.read<RecycleBinBloc>().stream.firstWhere(
                (newState) =>
                    newState is RecycleBinSuccess ||
                    newState is RecycleBinFailure,
              );
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: blogs.length,
              itemBuilder: (context, index) {
                final blog = blogs[index];
                final restoring = restoringArticleId == blog.articleId;
                return ListTile(
                  leading: blog.imageUrl.isEmpty
                      ? null
                      : SizedBox(
                          width: 48,
                          height: 48,
                          child: Image.network(
                            blog.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox(),
                          ),
                        ),
                  title: Text(
                    blog.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '删除于 ${blog.deletedAt.toLocal().toString().substring(0, 10)}'
                    ' · ${_purgeDeadlineText(blog)}',
                  ),
                  trailing: restoring
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => context.read<RecycleBinBloc>().add(
                            RecycleBinRestoreRequested(
                              articleId: blog.articleId,
                            ),
                          ),
                          child: const Text('恢复'),
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
