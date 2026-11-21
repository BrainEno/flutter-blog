import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// A note at the foot of a list that stopped early: why it stopped, and at
/// most one way on.
///
/// Two lists stop before their end: the next page failed to load, or the
/// order only goes so deep (`popular` is re-ranked while it is read). Each
/// used to set its own sentence and plain `TextButton` - some in body type,
/// some in meta type, some with a gap and some without. This is the one
/// footer for both:
///
/// * the sentence in [NoWaveTypography.metaLabel], muted and centred within
///   [NoWaveSizes.statusMeasure], the same voice as the "loading more" label
///   it replaces, so the foot of the list does not jump from a whisper to a
///   headline;
/// * a quiet [NoWaveButton] under it (text only, still a 48pt target) - a
///   footer is not the page's main action, so it takes no border or fill.
///
/// It is the small sibling of `NoWaveStatus`, which is for a whole list that
/// is empty or failed. Set [live] when the note appears because of something
/// the reader did not watch happen (a page failing in the background), so a
/// screen reader hears it; a standing note such as the depth limit stays
/// quiet.
class NoWaveListNote extends StatelessWidget {
  const NoWaveListNote({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.live = false,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Whether the note is announced when it appears.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final onAction = this.onAction;
    return Semantics(
      container: true,
      liveRegion: live,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: NoWaveSizes.statusMeasure,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: NoWaveTypography.metaLabel(
                    context,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onAction != null) ...[
                  const SizedBox(height: NoWaveSpacing.xs),
                  NoWaveButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    variant: NoWaveButtonVariant.quiet,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
