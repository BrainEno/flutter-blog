import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One comment and, recursively, its replies.
///
/// Reads the viewer identity and the delete progress from the route-scoped
/// blocs so the thread above only passes the intent callbacks.
class CommentTile extends StatelessWidget {
  final Comment comment;
  final int depth;
  final void Function(Comment) onReply;
  final ValueChanged<String> onOpenAuthor;
  final Future<bool> Function() confirmDelete;

  const CommentTile({
    super.key,
    required this.comment,
    required this.depth,
    required this.onReply,
    required this.onOpenAuthor,
    required this.confirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final appUserState = context.watch<AppUserCubit>().state;
    final viewerId = appUserState is AppUserLoggedIn
        ? appUserState.user.id
        : null;
    final isOwn = viewerId != null && viewerId == comment.authorId;
    final authorName = commentAuthorDisplayName(
      context.l10n,
      comment.authorName,
    );
    final deleting = context.select<CommentBloc, bool>(
      (bloc) => bloc.state.deletingIds.contains(comment.id),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Both avatar and name open the author's public profile.
              Semantics(
                label: context.l10n.authorPageSemantic(authorName),
                button: true,
                child: InkWell(
                  onTap: () => onOpenAuthor(comment.authorId),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: NoWaveAvatar(
                        name: authorName,
                        imageUrl: comment.authorAvatarUrl,
                        size: depth == 0 ? 32 : 26,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => onOpenAuthor(comment.authorId),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            authorName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      formatDate(
                        Localizations.localeOf(context),
                        comment.createdAt,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Plain-text rendering (content version 0): no markup
                    // is interpreted, the body renders exactly as stored.
                    Text(
                      comment.content,
                      style: TextStyle(
                        fontSize: depth == 0 ? 15 : 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _ActionText(
                          label: context.l10n.actionReply,
                          onPressed: () => onReply(comment),
                        ),
                        if (isOwn) ...[
                          const SizedBox(width: 16),
                          _ActionText(
                            label: deleting
                                ? context.l10n.commentDeleting
                                : context.l10n.actionDelete,
                            onPressed: deleting
                                ? null
                                : () async {
                                    if (await confirmDelete()) {
                                      // ignore: use_build_context_synchronously
                                      context.read<CommentBloc>().add(
                                        CommentDeleteRequested(comment.id),
                                      );
                                    }
                                  },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (comment.replies.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: depth == 0 ? 42 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: comment.replies
                    .map(
                      (reply) => CommentTile(
                        comment: reply,
                        depth: depth + 1,
                        onReply: onReply,
                        onOpenAuthor: onOpenAuthor,
                        confirmDelete: confirmDelete,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionText extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _ActionText({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: onPressed, child: Text(label));
  }
}
