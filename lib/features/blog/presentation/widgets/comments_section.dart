import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Comment thread under a viewed article (issue #19).
///
/// Lists the server's tree oldest-first with replies nested under their
/// direct parent, renders comment bodies as plain text (content version
/// 0), offers a composer to signed-in readers and a login prompt
/// otherwise. Deleting one's own comment asks for confirmation because
/// the server cascades the delete to the whole reply subtree.
class CommentsSection extends StatefulWidget {
  final String slug;
  final VoidCallback? onRequestLogin;

  const CommentsSection({super.key, required this.slug, this.onRequestLogin});

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Comment the composer currently replies to; null for a top-level
  /// comment.
  Comment? _replyTo;

  @override
  void initState() {
    super.initState();
    context.read<CommentBloc>().add(const CommentsRequested());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startReply(Comment comment) {
    setState(() => _replyTo = comment);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  String get _replyTargetName {
    final name = _replyTo?.authorName ?? '';
    return name.isNotEmpty ? name : context.l10n.anonymousReader;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.commentDeleteTitle),
        content: Text(l10n.commentDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              l10n.actionDelete,
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _submit() {
    context.read<CommentBloc>().add(
      CommentSubmitted(
        content: _controller.text,
        parentCommentId: _replyTo?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appUserState = context.watch<AppUserCubit>().state;
    final signedIn = appUserState is AppUserLoggedIn;

    return BlocConsumer<CommentBloc, CommentState>(
      listenWhen: (previous, current) =>
          previous.error != current.error ||
          (previous.submitting && !current.submitting),
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          // Load failures render inline next to their retry button;
          // submit/delete failures surface as a snackbar instead.
          if (state.status != CommentListStatus.failure) {
            showSnackBar(
              context,
              localizedFailureOr(context.l10n, state.failure, state.error),
            );
          }
          return;
        }
        // No error and a submit just finished: the server echoed the
        // stored comment, so the composer can be cleared. Failed submits
        // keep the text (and the bloc keeps the idempotency key) for a
        // safe retry.
        _controller.clear();
        _cancelReply();
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  context.l10n.commentsTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatNumber(
                    Localizations.localeOf(context),
                    state.totalCount,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!signedIn) _buildLoginPrompt() else _buildComposer(state),
            const SizedBox(height: 16),
            _buildList(state),
          ],
        );
      },
    );
  }

  Widget _buildLoginPrompt() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha((0.1 * 255).toInt()),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            context.l10n.loginToComment,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: widget.onRequestLogin,
            child: Text(context.l10n.goSignIn),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(CommentState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_replyTo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.reply, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _cancelReply,
                  tooltip: context.l10n.cancelReplyTooltip,
                ),
              ),
              child: Text(
                context.l10n.replyToLabel(_replyTargetName),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !state.submitting,
          maxLines: 4,
          minLines: 1,
          textInputAction: TextInputAction.newline,
          maxLength: CommentBloc.maxContentLength,
          decoration: InputDecoration(
            hintText: context.l10n.commentComposerHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: state.submitting ? null : _submit,
            icon: state.submitting
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: context.l10n.loading,
                    ),
                  )
                : const Icon(Icons.send, size: 16),
            label: Text(context.l10n.actionSend),
          ),
        ),
      ],
    );
  }

  Widget _buildList(CommentState state) {
    switch (state.status) {
      case CommentListStatus.initial:
      case CommentListStatus.loading:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(
              semanticsLabel: context.l10n.loading,
            ),
          ),
        );
      case CommentListStatus.failure:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Text(
                state.error.isNotEmpty
                    ? localizedFailureOr(
                        context.l10n,
                        state.failure,
                        state.error,
                      )
                    : context.l10n.commentsLoadFailed,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () =>
                    context.read<CommentBloc>().add(const CommentsRequested()),
                child: Text(context.l10n.actionRetry),
              ),
            ],
          ),
        );
      case CommentListStatus.loaded:
        if (state.comments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                context.l10n.commentsEmpty,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }
        return Column(
          children: state.comments
              .map(
                (comment) => _CommentTile(
                  comment: comment,
                  depth: 0,
                  onReply: _startReply,
                  confirmDelete: () => _confirmDelete(context),
                ),
              )
              .toList(),
        );
    }
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final int depth;
  final void Function(Comment) onReply;
  final Future<bool> Function() confirmDelete;

  const _CommentTile({
    required this.comment,
    required this.depth,
    required this.onReply,
    required this.confirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final appUserState = context.watch<AppUserCubit>().state;
    final viewerId = appUserState is AppUserLoggedIn
        ? appUserState.user.id
        : null;
    final isOwn = viewerId != null && viewerId == comment.authorId;
    final authorName = comment.authorName.trim().isNotEmpty
        ? comment.authorName
        : context.l10n.anonymousReader;
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
                  onTap: () => context.push('/author/${comment.authorId}'),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Semantics(
                        image: true,
                        label: context.l10n.avatarOf(authorName),
                        child: CircleAvatar(
                          radius: depth == 0 ? 16 : 13,
                          backgroundImage: comment.authorAvatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(
                                  comment.authorAvatarUrl,
                                )
                              : null,
                          child: comment.authorAvatarUrl.isEmpty
                              ? Icon(Icons.person, size: depth == 0 ? 16 : 13)
                              : null,
                        ),
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
                      onTap: () => context.push('/author/${comment.authorId}'),
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
                      (reply) => _CommentTile(
                        comment: reply,
                        depth: depth + 1,
                        onReply: onReply,
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
