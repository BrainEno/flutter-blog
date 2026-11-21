import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:flutter/material.dart';

/// The player, docked at the foot of the article once its full controls
/// have scrolled away.
///
/// Listening is something you keep doing while you read elsewhere in the
/// piece, so pause and stop must not live only at the top: the reader used
/// to have to scroll all the way back to stop the voice. The dock carries the
/// two buttons and how far in the voice is, with a thin ink rule on its top
/// edge for the same progress. When the reader has scrolled away from the
/// sentence being read, the caption gives way to the way back to it
/// ([onReturn]), pointing up or down to where the voice is.
class ReadAloudDock extends StatelessWidget {
  const ReadAloudDock({
    super.key,
    required this.controller,
    this.voiceAway,
    this.onReturn,
  });

  final ReadAloudController controller;

  /// Where the sentence being read is, when the reader has scrolled away
  /// from it; null while the page follows the voice.
  final VerticalDirection? voiceAway;

  /// Brings the sentence being read back into view.
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final playing = controller.phase == ReadAloudPhase.playing;
        final caption = playing
            ? l10n.readAloudListening(controller.percent)
            : l10n.readAloudPaused(controller.percent);
        final away = voiceAway;
        return Material(
          key: const ValueKey('read-aloud-dock'),
          color: theme.scaffoldBackgroundColor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: hairline, width: NoWaveStroke.hairline),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: NoWaveSizes.tabBar,
                child: Stack(
                  children: [
                    // How far in, as ink on the top edge.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: NoWaveSizes.accentRule,
                      child: ExcludeSemantics(
                        child: FractionallySizedBox(
                          key: const ValueKey('read-aloud-dock-progress'),
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: controller.progress.clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: ColoredBox(color: scheme.onSurface),
                        ),
                      ),
                    ),
                    Padding(
                      // The buttons carry their own inset; this puts their
                      // glyphs, not their hit areas, on the page gutter.
                      padding: const EdgeInsets.symmetric(
                        horizontal: NoWaveSpacing.page - NoWaveSpacing.small,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('read-aloud-dock-play'),
                            tooltip: playing
                                ? l10n.readAloudPause
                                : l10n.readAloudResume,
                            onPressed: controller.togglePlayback,
                            icon: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: NoWaveSpacing.xs),
                          Expanded(
                            // Away from the voice, the way back takes the
                            // caption's place: it is what the reader needs
                            // then, and the rule above still shows how far in.
                            child: away != null && onReturn != null
                                ? Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton.icon(
                                      key: const ValueKey('read-aloud-return'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: scheme.onSurface,
                                      ),
                                      onPressed: onReturn,
                                      icon: Icon(
                                        away == VerticalDirection.up
                                            ? Icons.arrow_upward
                                            : Icons.arrow_downward,
                                        size: NoWaveIconSize.inline,
                                      ),
                                      label: Text(
                                        l10n.readAloudReturn,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                : Text(
                                    caption,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: NoWaveTypography.meta(context)
                                        .copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                          ),
                          IconButton(
                            key: const ValueKey('read-aloud-dock-stop'),
                            tooltip: l10n.readAloudStop,
                            onPressed: controller.stop,
                            icon: Icon(Icons.stop, color: scheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
