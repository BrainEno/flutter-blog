import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// Where an article ends: a small ink square between two hairlines, and
/// one line of colophon under it.
///
/// On a phone the body runs straight into "related reading" and comments, and
/// a reader cannot tell the last paragraph from a pause. Magazines solve this
/// with an end mark - a small solid square after the final line - so the eye
/// knows the piece is over before it reaches anything else. This is that
/// mark, set as a section break so it holds its own line at every width.
///
/// The square is set in the text colour - the printer's tombstone is black,
/// and structure in this app is ink; orange is kept for what answers a touch
/// (focus, a pull that will refresh, reading progress). The hairlines and the square are
/// decoration. The colophon is read as written - [label], then the [byline]
/// when there is one - so a screen-reader user hears where the article ends
/// as clearly as a sighted reader sees it.
class NoWaveEndMark extends StatelessWidget {
  const NoWaveEndMark({
    super.key,
    required this.label,
    this.byline,
    this.ruled = true,
  });

  /// Whether hairlines run out from the square. A list's end keeps them; an
  /// article's end sets the square alone, above a change of paper that
  /// already makes the break.
  final bool ruled;

  /// What the colophon says first ("The end").
  final String label;

  /// Who wrote it, already phrased ("Words by …"); omitted when unknown.
  final String? byline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The same line as a Divider, drawn in two halves around the square.
    final hairline = theme.dividerTheme.color ?? scheme.outlineVariant;
    final byline = this.byline;
    return Semantics(
      container: true,
      child: Column(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                if (ruled) ...[
                  Expanded(
                    child: SizedBox(
                      height: NoWaveStroke.hairline,
                      child: ColoredBox(color: hairline),
                    ),
                  ),
                  const SizedBox(width: NoWaveSpacing.medium),
                ] else
                  const Spacer(),
                SizedBox.square(
                  key: const ValueKey('no-wave-end-mark'),
                  dimension: NoWaveSizes.endMark,
                  child: ColoredBox(color: scheme.onSurface),
                ),
                if (ruled) ...[
                  const SizedBox(width: NoWaveSpacing.medium),
                  Expanded(
                    child: SizedBox(
                      height: NoWaveStroke.hairline,
                      child: ColoredBox(color: hairline),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            byline == null ? label : '$label · $byline',
            textAlign: TextAlign.center,
            style: NoWaveTypography.metaLabel(
              context,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
