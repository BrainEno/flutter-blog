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
      padding: const EdgeInsets.symmetric(
        horizontal: NoWaveSpacing.medium,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        // A theme role instead of a fixed 10 % grey (issue #24): the tint
        // keeps its contrast against both the light and the dark paper.
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            context.l10n.loginToComment,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NoWaveSpacing.medium),
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
