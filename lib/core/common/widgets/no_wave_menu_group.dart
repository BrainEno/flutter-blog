import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// A run of action rows under a small heading, closed by a hairline so the
/// group reads as one block - the profile menu, the about page.
///
/// The heading is a plain muted label, not an eyebrow: it names what is
/// below it so a long menu can be scanned, and says nothing else. [title] is
/// null for a closing group that needs no name.
class NoWaveMenuGroup extends StatelessWidget {
  const NoWaveMenuGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = this.title;
    return Padding(
      padding: const EdgeInsets.only(top: NoWaveSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: NoWaveSpacing.small),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: NoWaveTypography.metaLabel(
                    context,
                    color: scheme.onSurfaceVariant,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ...children,
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha),
          ),
        ],
      ),
    );
  }
}
