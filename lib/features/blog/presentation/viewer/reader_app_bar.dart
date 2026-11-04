import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/article_share.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The article reader's app bar: share (only when a canonical URL exists) and
/// the save/like toggle.
///
/// Both actions need only the route-scoped `BlogLikedBloc` and `AppUserCubit`,
/// so this widget reads them from the context instead of taking callbacks.
class ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ReaderAppBar({
    super.key,
    required this.blog,
    required this.onRequestLogin,
  });

  final Blog blog;

  /// Opens the login flow, keeping the current location as the redirect.
  final VoidCallback onRequestLogin;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actions: [
        // Only share a canonical URL when WEB_BASE_URL is configured.
        if (articleWebUrl(blog.id) != null)
          IconButton(
            tooltip: context.l10n.shareArticleTooltip,
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareArticle(title: blog.title, slug: blog.id),
          ),
        BlocConsumer<BlogLikedBloc, BlogLikedState>(
          listener: (context, state) {
            if (state is ToggleBlogLikeFailure) {
              showSnackBar(
                context,
                localizedFailure(context.l10n, state.failure),
              );
            }
          },
          builder: (context, state) {
            final isSaved = state.likedBlogs[blog.id] ?? false;
            return IconButton(
              tooltip: isSaved
                  ? context.l10n.unsaveTooltip
                  : context.l10n.saveTooltip,
              icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () {
                final userState = context.read<AppUserCubit>().state;
                if (userState is AppUserLoggedIn) {
                  context.read<BlogLikedBloc>().add(
                    ToggleBlogLike(userId: userState.user.id, blogId: blog.id),
                  );
                } else {
                  showSnackBar(context, context.l10n.signInRequired);
                  onRequestLogin();
                }
              },
            );
          },
        ),
      ],
    );
  }
}
