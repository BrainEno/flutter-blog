import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// An editorial action row. Navigation and side effects belong to the caller.
class NoWaveActionRow extends StatelessWidget {
  const NoWaveActionRow({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.description,
    this.trailing,
  });

  final String label;
  final String? description;
  final IconData icon;
  final VoidCallback onTap;

  /// Shown between the label block and the chevron, for a count or a state the
  /// row itself does not describe (an unread notification badge, say).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        focusColor: AppPalette.orange.withAlpha(NoWaveOpacity.focusAlpha),
        child: Container(
          constraints: const BoxConstraints(minHeight: NoWaveSizes.row),
          padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, size: NoWaveIconSize.action)),
              const SizedBox(width: NoWaveSpacing.medium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: NoWaveTypography.title(context, size: 20),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: NoWaveSpacing.xs),
                      Text(
                        description!,
                        style: Theme.of(context).textTheme.bodySmall,
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
              const ExcludeSemantics(
                child: Icon(Icons.arrow_forward, size: NoWaveIconSize.row),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
