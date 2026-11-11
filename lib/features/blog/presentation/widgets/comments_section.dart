import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/comments/comment_composer.dart';
import 'package:belog/features/blog/presentation/comments/comment_login_prompt.dart';
import 'package:belog/features/blog/presentation/comments/comment_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Comment thread under a viewed article (issue #19).
///
/// Lists the server's tree oldest-first with replies nested under their
/// direct parent, renders comment bodies as plain text (content version
/// 0), offers a composer to signed-in readers and a login prompt
/// otherwise. Deleting one's own comment asks for confirmation because
/// the server cascades the delete to the whole reply subtree.
///
/// This widget owns the bloc interaction and the composer's state (text,
/// reply target, focus); [CommentComposer], [CommentLoginPrompt] and
/// [CommentTile] render it.
class CommentsSection extends StatefulWidget {
  final String slug;
  final VoidCallback? onRequestLogin;
  final ValueChanged<String> onOpenAuthor;

  const CommentsSection({
    super.key,
    required this.slug,
    required this.onOpenAuthor,
    this.onRequestLogin,
  });

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

  Future<bool> _confirmDelete(BuildContext context) {
    final l10n = context.l10n;
    // Deleting someone's comment cannot be undone, so it goes through the
    // shared destructive dialog: error-coloured confirm, cancel first, and a
    // barrier tap counts as "no".
    return showNoWaveConfirmDialog(
      context,
      title: l10n.commentDeleteTitle,
      message: l10n.commentDeleteBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.actionDelete,
    );
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
          (current.error.isNotEmpty && previous.error != current.error) ||
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
              spacing: NoWaveSpacing.xs,
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
                  context.l10n.commentsLoadedCount(
                    formatNumber(
                      Localizations.localeOf(context),
                      state.totalCount,
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: NoWaveSpacing.medium),
            if (!signedIn)
              CommentLoginPrompt(onRequestLogin: widget.onRequestLogin)
            else
              CommentComposer(
                state: state,
                controller: _controller,
                focusNode: _focusNode,
                replyTo: _replyTo,
                onCancelReply: _cancelReply,
                onSubmit: _submit,
              ),
            const SizedBox(height: NoWaveSpacing.medium),
            _buildList(state),
          ],
        );
      },
    );
  }

  Widget _buildList(CommentState state) {
    switch (state.status) {
      case CommentListStatus.initial:
      case CommentListStatus.loading:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.large),
            child: NoWaveLoadingLabel(semanticLabel: context.l10n.loading),
          ),
        );
      case CommentListStatus.failure:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.large),
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NoWaveSpacing.large,
                ),
                child: Center(
                  child: Text(
                    context.l10n.commentsEmpty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              _buildPaginationFooter(state),
            ],
          );
        }
        return Column(
          children: [
            ...state.comments.map(
              (comment) => CommentTile(
                comment: comment,
                depth: 0,
                onReply: _startReply,
                onOpenAuthor: widget.onOpenAuthor,
                confirmDelete: () => _confirmDelete(context),
              ),
            ),
            _buildPaginationFooter(state),
          ],
        );
    }
  }

  Widget _buildPaginationFooter(CommentState state) {
    final l10n = context.l10n;
    if (state.isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
        child: NoWaveLoadingLabel(semanticLabel: l10n.commentsLoadingMore),
      );
    }
    if (state.loadMoreFailure != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
        child: Column(
          children: [
            Text(
              localizedFailureOr(
                l10n,
                state.loadMoreFailure,
                l10n.commentsLoadFailed,
              ),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () => context.read<CommentBloc>().add(
                const MoreCommentsRequested(),
              ),
              child: Text(l10n.actionRetry),
            ),
          ],
        ),
      );
    }
    if (state.paginationUnavailable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
        child: Text(
          l10n.commentsPaginationUnavailable,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!state.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.small),
      child: TextButton.icon(
        onPressed: () =>
            context.read<CommentBloc>().add(const MoreCommentsRequested()),
        icon: const Icon(Icons.expand_more),
        label: Text(l10n.commentsLoadMore),
      ),
    );
  }
}
