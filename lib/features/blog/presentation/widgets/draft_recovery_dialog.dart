import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

enum DraftRecoveryChoice { restore, discard, keepCurrent }

/// Asks before replacing the editor's current contents with a local draft.
Future<DraftRecoveryChoice?> showDraftRecoveryDialog(
  BuildContext context, {
  required bool isOlderThanPublished,
}) {
  return showDialog<DraftRecoveryChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.draftFoundTitle),
      content: Text(
        isOlderThanPublished
            ? context.l10n.draftOlderBody
            : context.l10n.draftReplaceBody,
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, DraftRecoveryChoice.keepCurrent),
          child: Text(context.l10n.draftKeepCurrent),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, DraftRecoveryChoice.discard),
          child: Text(context.l10n.draftDiscardAction),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, DraftRecoveryChoice.restore),
          child: Text(context.l10n.draftRestoreAction),
        ),
      ],
    ),
  );
}
