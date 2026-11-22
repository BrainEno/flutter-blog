import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:flutter/material.dart';

/// The offer to go back to where the reader left an article: a square ink
/// slip, the page's colours turned over, with the share already read set
/// in tabular figures after the words.
///
/// Ink rather than orange: it is a way back into the text, not a primary
/// action, and orange is kept for position and focus. It inverts with the
/// theme, so on the dark paper it is a slip of light paper.
class ResumeReadingSlip extends StatelessWidget {
  const ResumeReadingSlip({
    super.key,
    required this.progress,
    required this.onTap,
  });

  /// The share of the text read last time, from 0 to 1.
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final percent = formatPercent(Localizations.localeOf(context), progress);
    final ink = scheme.onSurface;
    final paper = scheme.surface;
    final words = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: paper, fontWeight: FontWeight.w600);
    return Semantics(
      button: true,
      label: l10n.articleResumeLabel(percent),
      excludeSemantics: true,
      child: Material(
        color: ink,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NoWaveSizes.tapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NoWaveSpacing.medium,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward,
                    size: NoWaveIconSize.inline,
                    color: paper,
                  ),
                  const SizedBox(width: NoWaveSpacing.small),
                  Flexible(child: Text(l10n.articleResume, style: words)),
                  const SizedBox(width: NoWaveSpacing.small),
                  Text(
                    percent,
                    style: NoWaveTypography.meta(context).copyWith(
                      color: paper,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
