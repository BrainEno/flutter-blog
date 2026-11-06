import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

enum DraftRecoveryChoice { restore, discard, keepCurrent }

/// Asks before replacing the editor's current contents with a local draft.
Future<DraftRecoveryChoice?> showDraftRecoveryDialog(
  BuildContext context, {
  required bool isOlderThanPublished,
  void Function(Route<DraftRecoveryChoice> route)? onRouteCreated,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<DraftRecoveryChoice>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.draftFoundTitle),
      content: Text(
        isOlderThanPublished
            ? context.l10n.draftOlderBody
            : context.l10n.draftReplaceBody,
      ),
      actions: [
        NoWaveButton(
          label: context.l10n.draftKeepCurrent,
          variant: NoWaveButtonVariant.quiet,
          onPressed: () =>
              Navigator.pop(context, DraftRecoveryChoice.keepCurrent),
        ),
        // Discarding is the one choice here that destroys something the reader
        // cannot get back, so it carries the error colour.
        NoWaveButton(
          label: context.l10n.draftDiscardAction,
          variant: NoWaveButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, DraftRecoveryChoice.discard),
        ),
        NoWaveButton(
          label: context.l10n.draftRestoreAction,
          variant: NoWaveButtonVariant.primary,
          onPressed: () => Navigator.pop(context, DraftRecoveryChoice.restore),
        ),
      ],
    ),
  );
  onRouteCreated?.call(route);
  return navigator.push(route);
}
