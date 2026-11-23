import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_list_note.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/components/no_wave_section_head.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/repositories/comment_draft_store.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/comments/comment_composer.dart';
import 'package:belog/features/blog/presentation/comments/comment_draft_keeper.dart';
import 'package:belog/features/blog/presentation/comments/comment_login_prompt.dart';
import 'package:belog/features/blog/presentation/comments/comment_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

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
///
/// What a signed-in reader types but does not send is kept on the device
/// ([CommentDraftStore], through [CommentDraftKeeper]) and is back in the box
/// the next time they open the article - after leaving it, after the app was
/// closed, or after signing in again. Sending it removes it; a failed send
/// keeps it.
class CommentsSection extends StatefulWidget {
  final String slug;
  final VoidCallback? onRequestLogin;
  final ValueChanged<String> onOpenAuthor;

  /// The article's author: their comments carry a small "author" badge.
  final String? articleAuthorId;

  /// Where unsent comments are kept; the app's registered store when null.
  /// Without either, the box simply starts empty every time.
  final CommentDraftStore? draftStore;

  const CommentsSection({
    super.key,
    required this.slug,
    required this.onOpenAuthor,
    this.onRequestLogin,
    this.articleAuthorId,
    this.draftStore,
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
  int _composerIdentityEpoch = 0;

  /// Keeps the box in step with the reader's saved draft; null when there is
  /// nowhere to keep one.
  CommentDraftKeeper? _drafts;
  AppLifecycleListener? _lifecycle;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    context.read<CommentBloc>().add(const CommentsRequested());
    final store = widget.draftStore ?? _registeredDraftStore();
    if (store != null) {
      final drafts = CommentDraftKeeper(
        store,
        slug: widget.slug,
        read: () => CommentDraft(
          text: _controller.text,
          parentCommentId: _replyTo?.id,
          parentAuthorName: _replyTo?.authorName ?? '',
        ),
        apply: _applyDraft,
      );
      _drafts = drafts;
      _controller.addListener(_onTextChanged);
      // Leaving the app may be the last thing that happens to it: keep the
      // typing now rather than after the quiet moment.
      _lifecycle = AppLifecycleListener(
        onHide: drafts.flush,
        onDetach: drafts.flush,
      );
      drafts.follow(_signedInUserId());
    }
  }

  /// The comment drafts are an extra, not part of commenting: an unregistered
  /// store leaves the box without them rather than failing the page.
  static CommentDraftStore? _registeredDraftStore() {
    final locator = GetIt.instance;
    return locator.isRegistered<CommentDraftStore>()
        ? locator<CommentDraftStore>()
        : null;
  }

  String? _signedInUserId() => _userIdOf(context.read<AppUserCubit>().state);

  void _onTextChanged() {
    // The controller also speaks up when only the cursor moves.
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    _drafts?.changed();
  }

  /// Puts a saved draft (or, when blank, nothing) in the box.
  void _applyDraft(CommentDraft draft) {
    _controller.value = TextEditingValue(
      text: draft.text,
      selection: TextSelection.collapsed(offset: draft.text.length),
    );
    _lastText = draft.text;
    final parentId = draft.parentCommentId;
    setState(() {
      _replyTo = parentId == null
          ? null
          : _findComment(
                  context.read<CommentBloc>().state.comments,
                  parentId,
                ) ??
                // The thread may not have loaded that far (or at all) yet;
                // the reply only needs the id and the name it answers.
                Comment(
                  id: parentId,
                  articleId: widget.slug,
                  authorId: '',
                  content: '',
                  authorName: draft.parentAuthorName,
                  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                );
    });
  }

  static Comment? _findComment(List<Comment> comments, String id) {
    for (final comment in comments) {
      if (comment.id == id) return comment;
      if (_findComment(comment.replies, id) case final reply?) return reply;
    }
    return null;
  }

  /// Throws the restored draft away, with a moment to change one's mind.
  void _discardDraft() {
    final drafts = _drafts;
    if (drafts == null) return;
    final discarded = drafts.read();
    final owner = drafts.owner;
    _controller.clear();
    _cancelReply();
    drafts.flush();
    final l10n = context.l10n;
    showSnackBar(
      context,
      l10n.commentDraftDiscarded,
      action: SnackBarAction(
        label: l10n.actionUndo,
        onPressed: () {
          // Only into the same reader's box, and never over new typing.
          if (!mounted ||
              drafts.owner != owner ||
              _controller.text.isNotEmpty ||
              _replyTo != null) {
            return;
          }
          _applyDraft(discarded);
          drafts
            ..changed()
            ..flush();
        },
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    // Reads the box one last time, so before the controller goes.
    _drafts?.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startReply(Comment comment) {
    // Check again at activation time: the session may have changed since the
    // row was built. A guest never selects a reply target or focuses a hidden
    // composer; login remains the host's existing flow.
    if (context.read<AppUserCubit>().state is! AppUserLoggedIn) {
      widget.onRequestLogin?.call();
      return;
    }
    setState(() => _replyTo = comment);
    _drafts?.changed();
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    if (_replyTo == null) return;
    setState(() => _replyTo = null);
    _drafts?.changed();
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
    final user = context.read<AppUserCubit>().state;
    final comments = context.read<CommentBloc>();
    final fence = comments.captureFence();
    if (comments.state.identityEpoch != _composerIdentityEpoch ||
        user is! AppUserLoggedIn ||
        fence == null ||
        user.user.id != fence.userId) {
      return;
    }
    comments.add(
      CommentSubmitted(
        content: _controller.text,
        parentCommentId: _replyTo?.id,
        fence: fence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appUserState = context.watch<AppUserCubit>().state;
    final signedIn = appUserState is AppUserLoggedIn;

    final section = BlocConsumer<CommentBloc, CommentState>(
      listenWhen: (previous, current) =>
          (current.error.isNotEmpty && previous.error != current.error) ||
          (previous.submitting && !current.submitting) ||
          previous.identityEpoch != current.identityEpoch,
      listener: (context, state) {
        if (state.identityEpoch != _composerIdentityEpoch) {
          _composerIdentityEpoch = state.identityEpoch;
          final drafts = _drafts;
          if (drafts == null) {
            _controller.clear();
            _cancelReply();
            return;
          }
          // The box is emptied for whoever is signed in now, but what was in
          // it is kept for the reader who typed it - not saved as "nothing"
          // over their draft, nor written under the next account.
          drafts
            ..flush()
            ..silently(() {
              _controller.clear();
              _cancelReply();
            })
            ..restore();
          return;
        }
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
        // safe retry - and keep it saved on the device too. A sent one is
        // no longer a draft.
        _controller.clear();
        _cancelReply();
        _drafts?.flush();
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The count is a figure about the list, not part of its name:
            // it sits flush right on the title's baseline.
            NoWaveSectionHead(
              title: context.l10n.commentsTitle,
              trailing: context.l10n.commentsLoadedCount(
                formatNumber(Localizations.localeOf(context), state.totalCount),
              ),
            ),
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
            if (signedIn && _drafts != null)
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _drafts?.showsRestored ?? false
                    ? NoWaveListNote(
                        key: const ValueKey('comment-draft-restored'),
                        message: context.l10n.commentDraftRestored,
                        actionLabel: context.l10n.commentDraftDiscard,
                        onAction: _discardDraft,
                      )
                    : const SizedBox.shrink(),
              ),
            const SizedBox(height: NoWaveSpacing.medium),
            _buildList(state, signedIn: signedIn),
          ],
        );
      },
    );
    if (_drafts == null) return section;
    // The box belongs to whoever is signed in: their draft comes back, the
    // previous reader's goes with them.
    return BlocListener<AppUserCubit, AppUserState>(
      listenWhen: (previous, current) =>
          _userIdOf(previous) != _userIdOf(current),
      listener: (context, state) => _drafts?.follow(_userIdOf(state)),
      child: section,
    );
  }

  static String? _userIdOf(AppUserState state) => switch (state) {
    AppUserLoggedIn(:final user) => user.id,
    _ => null,
  };

  Widget _buildList(CommentState state, {required bool signedIn}) {
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
          child: NoWaveStatus(
            message: state.error.isNotEmpty
                ? localizedFailureOr(context.l10n, state.failure, state.error)
                : context.l10n.commentsLoadFailed,
            actionLabel: context.l10n.actionRetry,
            onAction: () =>
                context.read<CommentBloc>().add(const CommentsRequested()),
          ),
        );
      case CommentListStatus.loaded:
        if (state.comments.isEmpty) {
          // On the column edge, like the composer above it and the
          // comments that will replace it.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NoWaveSpacing.medium,
                ),
                child: Text(
                  context.l10n.commentsEmpty,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              _buildPaginationFooter(state),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...state.comments.map(
              (comment) => CommentTile(
                comment: comment,
                depth: 0,
                onReply: signedIn || widget.onRequestLogin != null
                    ? _startReply
                    : null,
                replyRequiresLogin: !signedIn,
                onOpenAuthor: widget.onOpenAuthor,
                confirmDelete: () => _confirmDelete(context),
                articleAuthorId: widget.articleAuthorId,
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
      return NoWaveListNote(
        message: localizedFailureOr(
          l10n,
          state.loadMoreFailure,
          l10n.commentsLoadFailed,
        ),
        actionLabel: l10n.actionRetry,
        onAction: () =>
            context.read<CommentBloc>().add(const MoreCommentsRequested()),
        live: true,
      );
    }
    if (state.paginationUnavailable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
        child: Text(
          l10n.commentsPaginationUnavailable,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (!state.hasMore) return const SizedBox.shrink();
    // The way on spans the column under the last card, outlined in ink: a
    // plain button the thumb finds at the end of the stack, not one more
    // muted word that reads like a comment's action.
    return Padding(
      padding: const EdgeInsets.only(top: NoWaveSpacing.small),
      child: NoWaveButton(
        label: l10n.commentsLoadMore,
        icon: Icons.expand_more,
        variant: NoWaveButtonVariant.secondary,
        expand: true,
        onPressed: () =>
            context.read<CommentBloc>().add(const MoreCommentsRequested()),
      ),
    );
  }
}
