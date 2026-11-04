import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// A rectangular type label.
///
/// With [onTap] it becomes a real button: focusable, keyboard-activatable and
/// carrying a 48×48 tap target, while the drawn chip stays the same size as
/// the read-only label. Without it the label is inert, which is what list rows
/// that are already one big link use it for.
class ArticleTagLabel extends StatelessWidget {
  const ArticleTagLabel({super.key, required this.tag, this.onTap});

  /// The stored tag value (what the article carries), not a localized label.
  final String tag;

  /// Opens the tag's article list when provided.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final display = localizedTag(l10n, tag);
    final foreground = Theme.of(context).colorScheme.onSurface;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: foreground)),
      child: Text(
        display,
        style: NoWaveTypography.meta(
          context,
        ).copyWith(color: foreground, fontWeight: FontWeight.w500),
      ),
    );

    final handler = onTap;
    if (handler == null) return chip;

    return Semantics(
      button: true,
      label: l10n.tagBrowseSemantics(display),
      // The button's own semantics is excluded, so the action has to live on
      // this node - otherwise the screen reader would announce a button that
      // cannot be activated.
      onTap: handler,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: handler,
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            // The chip keeps its compact look; the button around it owns the
            // accessible target so labels in a wrap stay visually unchanged.
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
          ),
          child: chip,
        ),
      ),
    );
  }
}
