import 'package:belog/core/design/components/no_wave_running_head.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_stamp_switcher.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/article_share.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The article reader's app bar: text size (when the page can change it),
/// share (only when a canonical URL exists) and the save/like toggle.
///
/// Both actions need only the route-scoped `BlogLikedBloc` and `AppUserCubit`,
/// so this widget reads them from the context instead of taking callbacks.
class ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ReaderAppBar({
    super.key,
    required this.blog,
    required this.onRequestLogin,
    this.runningHead,
    this.onRunningHeadTap,
    this.onTextSize,
  });

  final Blog blog;

  /// Opens the login flow, keeping the current location as the redirect.
  final VoidCallback onRequestLogin;

  /// Whether the title has scrolled under the bar; the running head and the
  /// hairline under the bar show while it is true.
  final ValueListenable<bool>? runningHead;

  /// Usually: back to the top of the article.
  final VoidCallback? onRunningHeadTap;

  /// Opens the text-size sheet; no button without it.
  final VoidCallback? onTextSize;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final runningHead = this.runningHead;
    if (runningHead == null) return _bar(context, headVisible: false);
    return ValueListenableBuilder<bool>(
      valueListenable: runningHead,
      builder: (context, visible, _) => _bar(context, headVisible: visible),
    );
  }

  Widget _bar(BuildContext context, {required bool headVisible}) {
    final theme = Theme.of(context);
    final rule = theme.dividerTheme.color ?? theme.colorScheme.outlineVariant;
    return AppBar(
      title: runningHead == null
          ? null
          : NoWaveRunningHead(
              title: blog.title,
              visible: headVisible,
              semanticLabel: context.l10n.readerRunningHead(blog.title),
              onTap: onRunningHeadTap,
            ),
      // A hairline under the bar while text runs beneath it, the way a
      // printed running head sits on a rule; transparent at the top, where
      // nothing is under the bar. Material fades between the two.
      shape: Border(
        bottom: BorderSide(
          color: headVisible ? rule : rule.withAlpha(0),
          width: NoWaveStroke.hairline,
        ),
      ),
      actions: [
        if (onTextSize case final onTextSize?)
          IconButton(
            key: const ValueKey('reader-text-size'),
            tooltip: context.l10n.readerTextSizeTooltip,
            icon: const Icon(Icons.text_fields),
            onPressed: onTextSize,
          ),
        // Only share a canonical URL when WEB_BASE_URL is configured, and
        // never for the viewer's own draft: the public web page would not
        // exist for the recipient (issue #21, "don't share drafts").
        if (!blog.isDraft && articleWebUrl(blog.id) != null)
          IconButton(
            tooltip: context.l10n.shareArticleTooltip,
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareArticle(
              title: blog.title,
              slug: blog.id,
              // Title, excerpt, canonical URL - what the issue asks the
              // sheet to carry, and nothing that only exists on this device.
              summary: shareSummary(blog.content, maxChars: 120),
            ),
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
              icon: NoWaveStampSwitcher(
                child: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                  key: ValueKey(isSaved),
                ),
              ),
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
