import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// The head of a section that follows an article: "related reading",
/// "comments".
///
/// No rule. The end matter is set on its own sheet of darker paper, so the
/// break from the article is already made; inside it a head is told from the
/// rows under it by size alone - the title a step up the type scale, with an
/// optional figure set flush right on its baseline ("3 loaded") - and by the
/// [NoWaveSpacing.medium] it keeps below.
class NoWaveSectionHead extends StatelessWidget {
  const NoWaveSectionHead({super.key, required this.title, this.trailing});

  final String title;

  /// A quiet figure at the end of the line, already phrased.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trailing = this.trailing;
    return Padding(
      key: const ValueKey('no-wave-section-head'),
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: NoWaveTypography.title(
                  context,
                  size: NoWaveTypeScale.dialogTitle,
                ).copyWith(height: 1.25),
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
    );
  }
}
