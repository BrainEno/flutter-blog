import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// An editorial action row. Navigation and side effects belong to the caller.
///
/// Set as a menu item, not a headline: a sans label at
/// [NoWaveTypeScale.actionRow] beside a line glyph, centred on the glyph
/// when there is no description. A dozen of these stacked under an account
/// name used to be a dozen serif headings, and the page had no top.
class NoWaveActionRow extends StatelessWidget {
  const NoWaveActionRow({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.description,
    this.trailing,
    this.showArrow = true,
  });

  final String label;
  final String? description;
  final IconData icon;
  final VoidCallback onTap;

  /// Shown between the label block and the chevron, for a count or a state the
  /// row itself does not describe (an unread notification badge, say).
  final Widget? trailing;

  /// Whether the row ends in the forward arrow. An action that does not go
  /// anywhere - signing out - has no "next page" to point at.
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = this.description;
    // The same answer as an article card - ripple, orange focus and hover
    // wash, the arrow stepping forward - without the sink: a ruled full-width
    // row would pull its rule in from the edges.
    return NoWavePressable(
      onTap: onTap,
      sink: false,
      child: Container(
        constraints: const BoxConstraints(minHeight: NoWaveSizes.tapTarget),
        padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: description == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: NoWaveIconSize.action,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: NoWaveSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: NoWaveTypeScale.actionRow,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: NoWaveSpacing.xs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: NoWaveSpacing.small),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: NoWaveSpacing.small),
            ],
            if (showArrow) const NoWavePressArrow(),
          ],
        ),
      ),
    );
  }
}
