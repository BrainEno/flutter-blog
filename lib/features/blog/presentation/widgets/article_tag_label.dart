import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// A non-interactive, rectangular type label; it never changes stored tags.
class ArticleTagLabel extends StatelessWidget {
  const ArticleTagLabel({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: foreground)),
      child: Text(
        localizedTag(context.l10n, tag),
        style: NoWaveTypography.meta(
          context,
        ).copyWith(color: foreground, fontWeight: FontWeight.w500),
      ),
    );
  }
}
