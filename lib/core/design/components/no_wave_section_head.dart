import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// The head of a section that follows an article: "related reading",
/// "comments".
///
/// An ink rule across the column, the title, and an optional figure set
/// flush right on the title's baseline ("3 loaded"). The title sits in the
/// middle of the band - the same [NoWaveSpacing.medium] above and below -
/// so the rule over it and the first row's rule under it frame it evenly.
/// The rows under a head carry hairlines, so the heavier rule is what tells
/// a new section from the next item.
class NoWaveSectionHead extends StatelessWidget {
  const NoWaveSectionHead({super.key, required this.title, this.trailing});

  final String title;

  /// A quiet figure at the end of the line, already phrased.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trailing = this.trailing;
    return DecoratedBox(
      key: const ValueKey('no-wave-section-head'),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.onSurface, width: NoWaveStroke.focus),
        ),
      ),
      child: Padding(
        // The border paints inside the box, so the top inset clears it: the
        // gap is measured from the rule's lower edge.
        padding: const EdgeInsets.only(
          top: NoWaveSpacing.medium + NoWaveStroke.focus,
          bottom: NoWaveSpacing.medium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: NoWaveTypography.tight(
                    context,
                    size: NoWaveTypeScale.sectionTitle,
                  ).copyWith(height: 1.3),
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: NoWaveSpacing.medium),
              Text(
                trailing,
                style: NoWaveTypography.meta(
                  context,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
