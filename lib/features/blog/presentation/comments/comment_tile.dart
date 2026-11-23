import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/design/components/no_wave_badge.dart';
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
/// A thread's first comment is drawn on its own card of the page's paper;
/// its replies stay inside that card, hanging from a rail under its face.
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

  /// The article's author, whose comments carry a small badge; null when
  /// the host cannot say.
  final String? articleAuthorId;

  /// Whom this row answers, named on rows past the second level where
  /// replies stop stepping in; null elsewhere.
  final String? parentAuthorName;

  const CommentTile({
    super.key,
    required this.comment,
    required this.depth,
    required this.onReply,
    required this.replyRequiresLogin,
    required this.onOpenAuthor,
    required this.confirmDelete,
    this.articleAuthorId,
    this.parentAuthorName,
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

  /// Avatar side for a thread's first comment and for a reply: a reply's
  /// face is a step smaller, like its words.
  static const _rootAvatar = 36.0;
  static const _replyAvatar = 28.0;

  /// Space between the avatar and the text column - the same at every
  /// depth, so a reply's name sits as close to its face as a root's does.
  static const _avatarGap = NoWaveSpacing.small + NoWaveSpacing.xs;

  /// Where a thread's words start, measured from the inside of its card.
  static const rootTextColumn = _rootAvatar + _avatarGap;

  /// The inset of a thread's card: its face and words start this far in.
  static const cardInset = NoWaveSpacing.medium;

  @override
  Widget build(BuildContext context) {
    final root = depth == 0;
    final body = _comment(context, root: root);
    if (!root) return body;
    // Every conversation is its own sheet of the page's paper laid on the
    // darker end matter: where one thread stops and the next begins is a
    // visible edge, not a guess made from spacing. Flat and square like
    // every other surface; the bottom inset is short because the action
    // row already carries a full tap target's air under its words.
    return Padding(
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.small),
      child: DecoratedBox(
        key: ValueKey('comment-thread-${comment.id}'),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            cardInset,
            cardInset,
            cardInset,
            NoWaveSpacing.xs,
          ),
          child: body,
        ),
      ),
    );
  }

  Widget _comment(BuildContext context, {required bool root}) {
    final users = context.watch<AppUserCubit>();
    final revision = users.identityRevision.value;
    final appUserState = users.state;
    final viewerId = appUserState is AppUserLoggedIn
        ? appUserState.user.id
        : null;
    final isOwn = viewerId != null && viewerId == comment.authorId;
    final authorId = articleAuthorId;
    final byArticleAuthor =
        authorId != null && authorId.isNotEmpty && comment.authorId == authorId;
    final authorName = commentAuthorDisplayName(
      context.l10n,
      comment.authorName,
    );
    final deleting = context.select<CommentBloc, bool>(
      (bloc) => bloc.state.deletingIds.contains(comment.id),
    );

    final avatar = root ? _rootAvatar : _replyAvatar;
    // The text column: name, date, body and actions all start on it, and a
    // reply's avatar hangs from it.
    final column = avatar + _avatarGap;
    final scheme = Theme.of(context).colorScheme;
    // Four steps, told apart by size and weight before colour: the name is
    // the only bold ink, what was said is the largest regular type, and
    // when it was said is the smallest and muted. The actions sit between
    // the two muted sizes, weighted so they read as things to press.
    final nameStyle = NoWaveTypography.meta(context).copyWith(
      fontSize: NoWaveTypeScale.label,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: scheme.onSurface,
    );
    final dateStyle = NoWaveTypography.metaLabel(
      context,
      size: NoWaveTypeScale.caption,
      color: scheme.onSurfaceVariant,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final inReplyTo = parentAuthorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The head: the face, then who and when stacked beside it - the
        // name on top in bold, the date under it in small muted type - so
        // the avatar is centred on the whole head rather than on one line.
        Row(
          children: [
            // Both avatar and name open the author's public profile.
            Semantics(
              label: context.l10n.authorPageSemantic(authorName),
              button: true,
              child: InkWell(
                onTap: () => onOpenAuthor(comment.authorId),
                child: SizedBox(
                  width: column,
                  height: NoWaveSizes.tapTarget,
                  // On the column edge, like every other first glyph on
                  // the page; the rest of the target lies after it.
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: NoWaveAvatar(
                      name: authorName,
                      imageUrl: comment.authorAvatarUrl,
                      size: avatar,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: NoWaveSpacing.small,
                    runSpacing: NoWaveSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => onOpenAuthor(comment.authorId),
                        child: Text(authorName, style: nameStyle),
                      ),
                      // The writer of the piece answering in their own
                      // thread is the one voice a reader looks for.
                      if (byArticleAuthor)
                        NoWaveBadge(
                          label: context.l10n.commentArticleAuthor,
                          tone: NoWaveBadgeTone.neutral,
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: NoWaveSpacing.xs,
                    children: [
                      Text(
                        formatDate(
                          Localizations.localeOf(context),
                          comment.createdAt,
                        ),
                        style: dateStyle,
                      ),
                      if (comment.editedAt != null) ...[
                        ExcludeSemantics(child: Text('·', style: dateStyle)),
                        Text(context.l10n.commentEdited, style: dateStyle),
                      ],
                      // Past the second level replies stop stepping in, so
                      // the row names whom it answers instead.
                      if (inReplyTo != null) ...[
                        ExcludeSemantics(child: Text('·', style: dateStyle)),
                        Text(
                          context.l10n.commentInReplyTo(inReplyTo),
                          style: dateStyle,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: column,
            top: NoWaveSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plain-text rendering (content version 0): no markup is
              // interpreted, the body renders exactly as stored.
              Text(
                comment.content,
                style: TextStyle(
                  fontSize: root
                      ? NoWaveTypeScale.comment
                      : NoWaveTypeScale.label,
                  height: 1.6,
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
                    icon: Icons.reply,
                    emphasized: true,
                    onPressed: onReply == null ? null : () => onReply!(comment),
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
                          : () =>
                                _confirmCurrentDelete(context, users, revision),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (comment.replies.isNotEmpty) _replies(context, column: column),
      ],
    );
  }

  /// The answers to this comment.
  ///
  /// The first two levels step in to this comment's text column and hang
  /// from a rail drawn down from under its face, so which words answer
  /// which can be followed with a finger. Deeper (and legacy) threads stop
  /// stepping in to keep a readable measure; each of those rows names the
  /// comment it answers instead.
  Widget _replies(BuildContext context, {required double column}) {
    final tiles = [
      for (final reply in comment.replies)
        CommentTile(
          comment: reply,
          depth: depth + 1,
          onReply: onReply,
          replyRequiresLogin: replyRequiresLogin,
          onOpenAuthor: onOpenAuthor,
          confirmDelete: confirmDelete,
          articleAuthorId: articleAuthorId,
          parentAuthorName: depth + 1 > 2
              ? commentAuthorDisplayName(context.l10n, comment.authorName)
              : null,
        ),
    ];
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tiles,
    );
    if (depth >= 2) return list;
    final theme = Theme.of(context);
    final rail =
        theme.dividerTheme.color ??
        theme.colorScheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha);
    final avatar = column - _avatarGap;
    // The rail runs under the centre of this comment's face; the replies'
    // own faces start on its text column, exactly where they did before
    // the rail was drawn.
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: avatar / 2 - NoWaveStroke.focus / 2,
      ),
      child: DecoratedBox(
        key: ValueKey('comment-replies-${comment.id}'),
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: rail, width: NoWaveStroke.focus),
          ),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: column - avatar / 2 + NoWaveStroke.focus / 2,
          ),
          child: list,
        ),
      ),
    );
  }
}

class _ActionText extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool emphasized;
  final VoidCallback? onPressed;

  const _ActionText({
    required this.label,
    this.icon,
    this.emphasized = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Reply is the one thing a reader comes to a comment to do, so it is
    // set in ink with its glyph; edit and delete stay muted, like the
    // date. The first action starts on the body's edge, and each keeps a
    // full-height target.
    final scheme = Theme.of(context).colorScheme;
    final icon = this.icon;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: emphasized
            ? scheme.onSurface
            : scheme.onSurfaceVariant,
        padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.small),
        minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
        alignment: AlignmentDirectional.centerStart,
        textStyle: NoWaveTypography.meta(
          context,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      child: icon == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: NoWaveIconSize.inline),
                const SizedBox(width: NoWaveSpacing.xs),
                Flexible(child: Text(label)),
              ],
            ),
    );
  }
}
