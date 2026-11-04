import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Status of the background draft auto-save.
enum AutoSaveStatus { idle, saving, saved, failed }

/// Thin status line for the background draft auto-save, shown above the form.
class AutoSaveBanner extends StatelessWidget {
  const AutoSaveBanner({super.key, required this.status});

  final AutoSaveStatus status;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    switch (status) {
      case AutoSaveStatus.idle:
        return const SizedBox.shrink();
      case AutoSaveStatus.saving:
        return Text(
          context.l10n.autoSaveSaving,
          textAlign: TextAlign.center,
          style: style,
        );
      case AutoSaveStatus.saved:
        return Text(
          context.l10n.autoSaveSaved,
          textAlign: TextAlign.center,
          style: style,
        );
      case AutoSaveStatus.failed:
        return Text(
          context.l10n.autoSaveFailed,
          textAlign: TextAlign.center,
          style: style?.copyWith(color: Theme.of(context).colorScheme.error),
        );
    }
  }
}
