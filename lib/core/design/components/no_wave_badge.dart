import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// Where a [NoWaveBadge] sits, which decides its colours.
enum NoWaveBadgeTone {
  /// State the row owns: a draft, a pending send.
  emphasize,

  /// Descriptive metadata laid over a cover: the language edition.
  neutral,
}

/// A small square-cornered label laid over a cover or next to a title.
///
/// It replaced three copies of the same `DecoratedBox` + `Padding` + `Text`
/// (draft marker, edition marker, queued-send marker). Text is limited to one
/// line and ellipsised, so a long word cannot push a cover out of its grid
/// tile at 2x text scale.
class NoWaveBadge extends StatelessWidget {
  const NoWaveBadge({
    super.key,
    required this.label,
    this.tone = NoWaveBadgeTone.emphasize,
  });

  final String label;
  final NoWaveBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      NoWaveBadgeTone.emphasize => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      NoWaveBadgeTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(NoWaveRadius.badge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NoWaveSpacing.small,
          vertical: NoWaveSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
