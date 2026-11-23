import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final replyTarget = commentAuthorDisplayName(
      context.l10n,
      replyTo?.authorName,
    );
    // A card of the page's paper, like the threads under it and like the
    // sign-in prompt it replaces for guests: the place to write is one
    // more sheet in the stack, not a line floating on the end matter.
    return Container(
      key: const ValueKey('comment-composer-card'),
      width: double.infinity,
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.xs,
        NoWaveSpacing.medium,
        NoWaveSpacing.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyTo != null)
            Padding(
              padding: const EdgeInsets.only(top: NoWaveSpacing.small),
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
          // The field and its action share one line, the way a reply is
          // written under a letter: a ruled line to write on and a small,
          // square "send" at its end - not a full-width coloured slab that
          // outweighs the comments it is part of.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !state.submitting,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  maxLength: CommentBloc.maxContentLength,
                  // The count only matters near the limit; until then it is
                  // one more number under every comment box.
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        required maxLength,
                      }) => maxLength == null || currentLength < maxLength * 0.8
                      ? null
                      : Text('$currentLength / $maxLength'),
                  decoration: InputDecoration(
                    hintText: context.l10n.commentComposerHint,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: NoWaveSpacing.medium,
                    ),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: scheme.onSurface),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: scheme.onSurface),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: AppPalette.orange,
                        width: NoWaveStroke.focus,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: NoWaveSpacing.medium),
              NoWaveButton(
                label: context.l10n.actionSend,
                variant: NoWaveButtonVariant.secondary,
                isLoading: state.submitting,
                onPressed: state.submitting ? null : onSubmit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
