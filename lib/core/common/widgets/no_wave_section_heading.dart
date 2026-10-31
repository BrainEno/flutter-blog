import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// An editorial heading that wraps rather than clipping at large text sizes.
class NoWaveSectionHeading extends StatelessWidget {
  const NoWaveSectionHeading({
    super.key,
    required this.title,
    this.companion,
    this.eyebrow,
  });

  final String title;
  final String? companion;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final titleStyle = NoWaveTypography.title(context, size: 36);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!, style: NoWaveTypography.meta(context)),
          const SizedBox(height: 8),
        ],
        Semantics(
          header: true,
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(title, style: titleStyle),
              if (companion != null)
                Text(
                  companion!,
                  style: titleStyle.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
