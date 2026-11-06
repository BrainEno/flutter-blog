import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// Asks the reader to confirm one action and reports the answer.
///
/// Every irreversible action in the app (delete an article, end a session,
/// clear reading history) had its own copy of the same dialog: title, body,
/// cancel, confirm. They had drifted - one places the destructive button
/// first, one used a bare `TextButton` with a 40pt target, one had no cancel
/// path on the barrier - and each new screen copied whichever only it saw.
///
/// The contract enforced here:
///
/// - Cancelling is always reachable: the dialog is dismissible by the barrier,
///   the back gesture and Escape, all of which return false.
/// - The confirm button is [NoWaveButtonVariant.destructive] when
///   [destructive] is true, so the colour says what the words say.
/// - Focus starts on cancel, not on the action that deletes something.
/// - The returned future completes with false when the dialog is dismissed
///   without a choice, so callers cannot mistake "closed" for "confirmed".
Future<bool> showNoWaveConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.large,
        0,
        NoWaveSpacing.large,
        NoWaveSpacing.medium,
      ),
      actions: [
        NoWaveButton(
          label: cancelLabel,
          variant: NoWaveButtonVariant.quiet,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        NoWaveButton(
          label: confirmLabel,
          variant: destructive
              ? NoWaveButtonVariant.destructive
              : NoWaveButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
