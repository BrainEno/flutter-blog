import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// A text link that starts on the column edge.
///
/// A plain `TextButton` pads its label on both sides, so a link placed
/// under a heading or a name started a step in from everything it belonged
/// to - the profile's author link, an author's follower links, the about
/// page's addresses. This one keeps only the trailing inset (the gap to
/// whatever follows) and the 48pt target height.
///
/// [icon] leads the label; [forward] adds the arrow after it for a link that
/// opens another page.
class NoWaveLinkButton extends StatelessWidget {
  const NoWaveLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.forward = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.small),
        minimumSize: const Size(0, NoWaveSizes.tapTarget),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: NoWaveIconSize.inline),
            const SizedBox(width: NoWaveSpacing.small),
          ],
          Flexible(child: Text(label)),
          if (forward) ...[
            const SizedBox(width: NoWaveSpacing.xs),
            const Icon(Icons.arrow_forward, size: NoWaveIconSize.inline),
          ],
        ],
      ),
    );
  }
}
