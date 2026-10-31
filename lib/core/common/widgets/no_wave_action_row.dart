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
  });

  final String label;
  final String? description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        focusColor: AppPalette.orange.withAlpha(55),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.onSurface.withAlpha(100)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 22)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: NoWaveTypography.title(context, size: 20),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const ExcludeSemantics(
                child: Icon(Icons.arrow_forward, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
