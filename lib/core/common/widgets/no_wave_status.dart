import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// Quiet, reusable editorial empty/error state; wording and actions remain
/// the responsibility of the screen that owns the underlying state.
class NoWaveStatus extends StatelessWidget {
  const NoWaveStatus({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              '—',
              style: NoWaveTypography.title(context, size: 48).copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
