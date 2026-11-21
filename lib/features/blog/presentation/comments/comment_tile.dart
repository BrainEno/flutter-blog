import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/comments/comment_edit_guard.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/comments/comment_edit_dialog.dart';
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
    final fence = comments.captureFence();
    if (fence == null || fence.userId != comment.authorId) return;
    final confirmed = await confirmDelete();
    if (!confirmed || !context.mounted || comments.isClosed || !stillOwner()) {
      return;
    }
    if (!identical(context.read<AppUserCubit>(), users) ||
        !identical(context.read<CommentBloc>(), comments)) {
      return;
    }
    final currentFence = comments.captureFence();
    if (currentFence == null ||
        currentFence.userId != fence.userId ||
        currentFence.generation != fence.generation) {
      return;
    }
    comments.add(CommentDeleteRequested(comment.id, fence: fence));
  }

  Future<void> _openEditor(
    BuildContext context,
    AppUserCubit users,
    int revision,
  ) async {
    if (users.isClosed || users.identityRevision.value != revision) return;
    final user = users.state;
    final bloc = context.read<CommentBloc>();
    final fence = bloc.captureFence();
    if (user is! AppUserLoggedIn ||
        user.user.id != comment.authorId ||
        fence == null ||
        fence.userId != comment.authorId ||
        !CommentEditGuard.canEdit(
          comment,
          maxLength: CommentBloc.maxContentLength,
        ) ||
        bloc.isClosed) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CommentEditDialog(comment: comment, bloc: bloc, fence: fence),
    );
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

    // Replies hang from the parent's text column: their avatar starts where
    // the parent's name and body do.
    const indent = NoWaveSizes.listThumbnailSmall;
    final scheme = Theme.of(context).colorScheme;
    final quiet = NoWaveTypography.meta(
      context,
    ).copyWith(color: scheme.onSurfaceVariant);
    // Threads are told apart by space, not rules: each opens on its
    // author's face and name, and its replies hang from its text column,
    // so the eye reads one conversation per group.
    return Padding(
      padding: EdgeInsets.only(
        top: depth == 0 ? NoWaveSpacing.small : 0,
        bottom: depth == 0 ? NoWaveSpacing.large : NoWaveSpacing.xs,
      ),
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
                    // On the column edge, like every other first glyph on
                    // the page; the rest of the 48pt target lies after it.
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: NoWaveAvatar(
                        name: authorName,
                        imageUrl: comment.authorAvatarUrl,
                        size: depth == 0 ? 32 : 26,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and date on one line beside the avatar: who and
                    // when read as the comment's head, the body below it.
                    Wrap(
                      spacing: NoWaveSpacing.small,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => onOpenAuthor(comment.authorId),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: NoWaveSizes.tapTarget,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: 1,
                              child: Text(
                                authorName,
                                style: NoWaveTypography.meta(context).copyWith(
                                  fontSize: NoWaveTypeScale.label,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          formatDate(
                            Localizations.localeOf(context),
                            comment.createdAt,
                          ),
                          style: quiet,
                        ),
                        if (comment.editedAt != null)
                          Text(context.l10n.commentEdited, style: quiet),
                      ],
                    ),
                    // Plain-text rendering (content version 0): no markup
                    // is interpreted, the body renders exactly as stored.
                    Text(
                      comment.content,
                      style: TextStyle(
                        fontSize: depth == 0
                            ? NoWaveTypeScale.comment
                            : NoWaveTypeScale.label,
                        height: 1.65,
                        color: scheme.onSurface,
                      ),
                    ),
                    Wrap(
                      spacing: NoWaveSpacing.small,
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
                          if (CommentEditGuard.canEdit(
                            comment,
                            maxLength: CommentBloc.maxContentLength,
                          ))
                            _ActionText(
                              label: context.l10n.commentEditAction,
                              onPressed: deleting
                                  ? null
                                  : () => _openEditor(context, users, revision),
                            ),
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
                  ? const EdgeInsetsDirectional.only(start: indent)
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
    // Set like the date: the actions belong to the comment but should not
    // compete with what it says. The first one starts on the body's edge;
    // each keeps a full-height target.
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.small),
        minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
        alignment: AlignmentDirectional.centerStart,
        textStyle: NoWaveTypography.meta(
          context,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
