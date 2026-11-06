import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// How loud a [NoWaveNotice] is.
enum NoWaveNoticeTone {
  /// A fact about the list the reader is looking at: "each language is capped
  /// at 50", "drafts are private".
  info,

  /// Still usable, but the reader should know the limit: an older deployment,
  /// a partial list, a queued send.
  warning,

  /// Something failed. The notice carries the retry action when there is one.
  error,
}

/// An inline note between blocks of a page.
///
/// Screens used to write these as a bare `Padding` + `Text(bodySmall)` or, for
/// failures, a second copy of a red box. That made the voice and the spacing
/// inconsistent and left two problems unsolved:
///
/// - **Announcement.** [isLive] marks the notice as a live region, so a note
///   that appears after a long request is read out instead of being missed by
///   anyone not looking at the exact area.
/// - **Actionable.** An error notices usually has one thing to do (retry,
///   switch language). [actionLabel]/[onAction] keep that next to the message
///   instead of pushing it into a snackbar that disappears.
class NoWaveNotice extends StatelessWidget {
  const NoWaveNotice({
    super.key,
    required this.message,
    this.tone = NoWaveNoticeTone.info,
    this.actionLabel,
    this.onAction,
    this.isLive = false,
    this.icon,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;
  final NoWaveNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// True when the notice appears as the result of an action (a refresh, a
  /// failed send). Static explanatory notes stay false so a screen reader is
  /// not interrupted on every rebuild of a list header.
  final bool isLive;

  /// Overrides the tone's default glyph. The glyph is decorative and never
  /// carries meaning alone: the message always says what happened.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, defaultIcon) = switch (tone) {
      NoWaveNoticeTone.info => (scheme.onSurfaceVariant, Icons.info_outline),
      NoWaveNoticeTone.warning => (scheme.onSurface, Icons.report_outlined),
      NoWaveNoticeTone.error => (scheme.error, Icons.error_outline),
    };
    return Semantics(
      liveRegion: isLive,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: NoWaveStroke.focus),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.medium,
            vertical: NoWaveSpacing.small,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  icon ?? defaultIcon,
                  size: NoWaveIconSize.inline,
                  color: color,
                ),
              ),
              const SizedBox(width: NoWaveSpacing.small),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: color),
                    ),
                    if (onAction != null) ...[
                      const SizedBox(height: NoWaveSpacing.xs),
                      TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: color,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(
                            NoWaveSizes.tapTarget,
                            NoWaveSizes.tapTarget,
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
