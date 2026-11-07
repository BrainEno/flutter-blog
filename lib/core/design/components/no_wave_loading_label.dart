import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// The app's loading state: a rule and a word, never a spinner.
///
/// no-wave prints; it does not spin. A rotating indicator is the one thing on
/// screen that belongs to no typeface and no palette, and it says nothing a
/// sentence cannot. The label is real copy, so the reader knows *what* is
/// being waited for and the state survives a screenshot or a bug report.
///
/// It owns the announcement (`liveRegion`, exactly one label) which is why the
/// rule is inside [ExcludeSemantics]: a screen reader should hear the sentence,
/// not a line.
class NoWaveLoadingLabel extends StatelessWidget {
  const NoWaveLoadingLabel({
    super.key,
    this.label,
    this.semanticLabel,
    this.compact = false,
  });

  /// Visible copy. Defaults to [semanticLabel] and then to the generic
  /// `loadingLabel`, so a call site migrating from a spinner keeps the wording
  /// it already localized instead of losing it to a generic one.
  final String? label;

  /// What a screen reader announces. Defaults to the visible copy.
  final String? semanticLabel;

  /// Drops the rule: a list footer is a footnote, not a state.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha);
    final text = label ?? semanticLabel ?? context.l10n.loadingLabel;

    return Semantics(
      label: semanticLabel ?? text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              SizedBox(
                width: NoWaveSizes.loadingRule,
                height: NoWaveStroke.hairline,
                child: ColoredBox(color: muted),
              ),
              const SizedBox(height: NoWaveSpacing.small),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: NoWaveTypography.metaLabel(context, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
