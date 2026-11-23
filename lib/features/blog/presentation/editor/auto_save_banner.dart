import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Status of the background draft auto-save.
enum AutoSaveStatus { idle, saving, saved, failed }

/// Thin status line for the background draft auto-save, shown above the form.
///
/// A glyph beside the words makes the state readable at a glance - writing
/// feels safe when the author can see the draft is kept - and the line is a
/// live region, so a screen reader hears a failed save without looking.
class AutoSaveBanner extends StatelessWidget {
  const AutoSaveBanner({super.key, required this.status});

  final AutoSaveStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (IconData icon, String label, Color color) = switch (status) {
      AutoSaveStatus.idle => (Icons.circle, '', muted),
      AutoSaveStatus.saving => (Icons.sync, context.l10n.autoSaveSaving, muted),
      AutoSaveStatus.saved => (
        Icons.cloud_done_outlined,
        context.l10n.autoSaveSaved,
        muted,
      ),
      AutoSaveStatus.failed => (
        Icons.error_outline,
        context.l10n.autoSaveFailed,
        theme.colorScheme.error,
      ),
    };
    if (status == AutoSaveStatus.idle) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: NoWaveIconSize.row, color: color),
          ),
          const SizedBox(width: NoWaveSpacing.xs),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
