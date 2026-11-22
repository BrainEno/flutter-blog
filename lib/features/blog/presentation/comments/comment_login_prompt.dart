import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';

/// Shown instead of [CommentComposer] to signed-out readers.
class CommentLoginPrompt extends StatelessWidget {
  const CommentLoginPrompt({super.key, this.onRequestLogin});

  /// Opens the login flow; null when the host does not offer it.
  final VoidCallback? onRequestLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NoWaveSpacing.medium),
      decoration: BoxDecoration(
        // The comments sit on the article's darker end-matter sheet; the
        // prompt is a card of the page's own paper laid on it. A theme role
        // instead of a fixed grey (issue #24), so it holds in both themes.
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(NoWaveRadius.surface),
      ),
      // Set on the section's one left edge, like the comments under it: a
      // centred block here was the only thing in the thread on its own axis.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.loginToComment,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: NoWaveSpacing.small),
          NoWaveButton(
            label: context.l10n.goSignIn,
            variant: NoWaveButtonVariant.secondary,
            onPressed: onRequestLogin,
          ),
        ],
      ),
    );
  }
}
