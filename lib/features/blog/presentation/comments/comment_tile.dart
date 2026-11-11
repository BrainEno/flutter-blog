import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/design/design_tokens.dart';
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
  final void Function(Comment)? onReply;
  final bool replyRequiresLogin;
  final ValueChanged<String> onOpenAuthor;
  final Future<bool> Function() confirmDelete;

  const CommentTile({
    super.key,
    required this.comment,
    required this.depth,
    required this.onReply,
    required this.replyRequiresLogin,
    required this.onOpenAuthor,
    required this.confirmDelete,
  });

  Future<void> _confirmCurrentDelete(
    BuildContext context,
    AppUserCubit users,
    int revision,
  ) async {
    bool stillOwner() {
      if (users.isClosed || users.identityRevision.value != revision) {
        return false;
      }
      final state = users.state;
      return state is AppUserLoggedIn && state.user.id == comment.authorId;
    }

    if (!context.mounted || !stillOwner()) return;
    if (!identical(context.read<AppUserCubit>(), users)) return;
    final comments = context.read<CommentBloc>();
    if (comments.isClosed) return;
    final confirmed = await confirmDelete();
    if (!confirmed || !context.mounted || comments.isClosed || !stillOwner()) {
      return;
    }
    if (!identical(context.read<AppUserCubit>(), users) ||
        !identical(context.read<CommentBloc>(), comments)) {
      return;
    }
    comments.add(CommentDeleteRequested(comment.id));
  }

  @override
  Widget build(BuildContext context) {
    final users = context.watch<AppUserCubit>();
    final revision = users.identityRevision.value;
    final appUserState = users.state;
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

    final indent = depth == 0 ? 42.0 : 36.0; // design-token-ok: avatar column
    return Padding(
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
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
                  child: SizedBox.square(
                    dimension: NoWaveSizes.listThumbnailSmall,
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
              const SizedBox(width: NoWaveSpacing.small),
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
                    Wrap(
                      spacing: NoWaveSpacing.small,
                      children: [
                        Text(
                          formatDate(
                            Localizations.localeOf(context),
                            comment.createdAt,
                          ),
                        ),
                        if (comment.editedAt != null)
                          Text(context.l10n.commentEdited),
                      ],
                    ),
                    const SizedBox(height: NoWaveSpacing.xs),
                    // Plain-text rendering (content version 0): no markup
                    // is interpreted, the body renders exactly as stored.
                    Text(
                      comment.content,
                      style: TextStyle(
                        fontSize: depth == 0 ? 15 : 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: NoWaveSpacing.xs),
                    Wrap(
                      spacing: NoWaveSpacing.medium,
                      children: [
                        _ActionText(
                          label: replyRequiresLogin
                              ? context.l10n.signInToReply
                              : context.l10n.actionReply,
                          onPressed: onReply == null
                              ? null
                              : () => onReply!(comment),
                        ),
                        if (isOwn) ...[
                          _ActionText(
                            label: deleting
                                ? context.l10n.commentDeleting
                                : context.l10n.actionDelete,
                            onPressed: deleting
                                ? null
                                : () => _confirmCurrentDelete(
                                    context,
                                    users,
                                    revision,
                                  ),
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
              // Limit indentation for deep (including legacy) threads.
              padding: depth < 2
                  ? EdgeInsets.only(left: indent)
                  : EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: comment.replies
                    .map(
                      (reply) => CommentTile(
                        comment: reply,
                        depth: depth + 1,
                        onReply: onReply,
                        replyRequiresLogin: replyRequiresLogin,
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
