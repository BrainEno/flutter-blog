import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/utils/format_date.dart';
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
  String _purgeDeadlineText(AppLocalizations l10n, DeletedBlog blog) {
    final purgesAt = blog.purgesAt;
    if (purgesAt == null) {
      return l10n.purgeAfterRetention;
    }
    final days = purgesAt.difference(DateTime.now()).inDays + 1;
    if (days <= 0) {
      return l10n.purgeSoon;
    }
    return l10n.purgeInDays(days, formatNumber(Localizations.localeOf(context), days));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.recycleBinTitle),
        centerTitle: true,
      ),
      body: BlocConsumer<RecycleBinBloc, RecycleBinState>(
        listener: (context, state) {
          if (state is RecycleBinRestoreFailure) {
            showSnackBar(
              context,
              localizedFailure(context.l10n, state.failure),
            );
          } else if (state is RecycleBinSuccess) {
            final title = state.lastRestoredTitle;
            if (title != null) {
              showSnackBar(context, context.l10n.restoredAsDraft(title));
            }
          }
        },
        builder: (context, state) {
          if (state is RecycleBinLoading || state is RecycleBinInitial) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: context.l10n.loading,
              ),
            );
          }
          if (state is RecycleBinFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(localizedFailure(context.l10n, state.failure)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => context.read<RecycleBinBloc>().add(
                      RecycleBinRequested(),
                    ),
                    child: Text(context.l10n.actionRetry),
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
            return Center(child: Text(context.l10n.recycleBinEmpty));
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
                final deletedLabel = context.l10n.deletedOn(
                  formatDate(Localizations.localeOf(context), blog.deletedAt),
                );
                return ListTile(
                  leading: blog.imageUrl.isEmpty
                      ? null
                      : SizedBox(
                          width: 48,
                          height: 48,
                          child: Image.network(
                            blog.imageUrl,
                            fit: BoxFit.cover,
                            semanticLabel: context.l10n.coverOf(blog.title),
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
                    '$deletedLabel'
                    ' · ${_purgeDeadlineText(context.l10n, blog)}',
                  ),
                  trailing: restoring
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: context.l10n.loading,
                          ),
                        )
                      : TextButton(
                          onPressed: () => context.read<RecycleBinBloc>().add(
                            RecycleBinRestoreRequested(
                              articleId: blog.articleId,
                            ),
                          ),
                          child: Text(context.l10n.actionRestore),
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
