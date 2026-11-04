import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:flutter/material.dart';

/// The comment input: an optional "replying to" banner, the text field and the
/// send button.
///
/// Stateless on purpose - the text controller, focus node and reply target
/// stay with [CommentsSection] so a failed submit keeps the draft text.
class CommentComposer extends StatelessWidget {
  const CommentComposer({
    super.key,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.onCancelReply,
    required this.onSubmit,
  });

  final CommentState state;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// The comment being replied to; null for a top-level comment.
  final Comment? replyTo;

  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final replyName = replyTo?.authorName ?? '';
    final replyTarget = replyName.isNotEmpty
        ? replyName
        : context.l10n.anonymousReader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
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
                  onPressed: onCancelReply,
                  tooltip: context.l10n.cancelReplyTooltip,
                ),
              ),
              child: Text(
                context.l10n.replyToLabel(replyTarget),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        TextField(
          controller: controller,
          focusNode: focusNode,
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
            onPressed: state.submitting ? null : onSubmit,
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
}
