import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:flutter/material.dart';

/// Compact, keyboard- and screen-reader-accessible article player.
class ReadAloudControls extends StatefulWidget {
  const ReadAloudControls({super.key, required this.controller});
  final ReadAloudController controller;

  @override
  State<ReadAloudControls> createState() => _ReadAloudControlsState();
}

class _ReadAloudControlsState extends State<ReadAloudControls> {
  bool _dragging = false;
  bool _cancelled = false;

  @override
  void didUpdateWidget(covariant ReadAloudControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _dragging = false;
      _cancelled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (!controller.available) return const SizedBox.shrink();
        final active = controller.phase != ReadAloudPhase.idle;
        final label = switch (controller.phase) {
          ReadAloudPhase.idle => l10n.readAloudListen,
          ReadAloudPhase.playing => l10n.readAloudPause,
          ReadAloudPhase.paused => l10n.readAloudResume,
        };
        final caption = switch (controller.phase) {
          ReadAloudPhase.playing => l10n.readAloudListening(controller.percent),
          ReadAloudPhase.paused => l10n.readAloudPaused(controller.percent),
          ReadAloudPhase.idle => switch (controller.notice) {
            ReadAloudNotice.hint => l10n.readAloudHint,
            ReadAloudNotice.stopped => l10n.readAloudStopped,
            ReadAloudNotice.finished => l10n.readAloudFinished,
            ReadAloudNotice.error => l10n.readAloudError,
          },
        };
        final scheme = Theme.of(context).colorScheme;
        return Container(
          key: const ValueKey('read-aloud-controls'),
          margin: const EdgeInsets.only(bottom: NoWaveSpacing.section),
          padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.small),
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: scheme.onSurface.withAlpha(70)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: NoWaveSpacing.small,
                runSpacing: NoWaveSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: const ValueKey('read-aloud-play'),
                    onPressed: controller.togglePlayback,
                    icon: Icon(
                      controller.phase == ReadAloudPhase.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    label: Text(label),
                  ),
                  if (active)
                    IconButton(
                      key: const ValueKey('read-aloud-stop'),
                      tooltip: l10n.readAloudStop,
                      onPressed: controller.stop,
                      icon: const Icon(Icons.stop),
                    ),
                  Wrap(
                    spacing: NoWaveSpacing.small,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.readAloudSpeed,
                        style: NoWaveTypography.meta(context),
                      ),
                      Semantics(
                        label: l10n.readAloudSpeed,
                        child: DropdownButton<double>(
                          key: const ValueKey('read-aloud-speed'),
                          value: controller.speed,
                          items: [
                            for (final value in ReadAloudController.speeds)
                              DropdownMenuItem<double>(
                                value: value,
                                child: Text(
                                  '${value.toString().replaceFirst(RegExp(r'\.0$'), '')}×',
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) controller.setSpeed(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  Tooltip(
                    message: l10n.readAloudFollowHint,
                    child: MergeSemantics(
                      child: InkWell(
                        onTap: () => controller.setFollow(!controller.follow),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Checkbox(
                              key: const ValueKey('read-aloud-follow'),
                              value: controller.follow,
                              onChanged: (value) =>
                                  controller.setFollow(value ?? false),
                            ),
                            Text(l10n.readAloudFollow),
                            const SizedBox(width: NoWaveSpacing.small),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Semantics(
                liveRegion:
                    !active && controller.notice != ReadAloudNotice.hint,
                child: Text(
                  caption,
                  style: NoWaveTypography.meta(context).copyWith(
                    color: controller.notice == ReadAloudNotice.error && !active
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Tooltip(
                message: l10n.readAloudSeekHint,
                child: Semantics(
                  label: l10n.readAloudSeek,
                  child: Listener(
                    onPointerCancel: (_) {
                      if (_dragging) {
                        _dragging = false;
                        _cancelled = true;
                        controller.cancelSeek();
                      }
                    },
                    child: SliderTheme(
                      data: SliderTheme.of(
                        context,
                      ).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
                      child: Slider(
                        key: const ValueKey('read-aloud-seek'),
                        value: controller.progress.clamp(0.0, 1.0),
                        divisions: 1000,
                        semanticFormatterCallback: (value) =>
                            l10n.readAloudPercent((value * 100).round()),
                        onChangeStart: active
                            ? (_) {
                                _cancelled = false;
                                _dragging = true;
                              }
                            : null,
                        onChanged: active
                            ? (value) {
                                if (_cancelled) return;
                                controller.previewSeek(value);
                                // Keyboard/assistive adjustments may not have a
                                // pointer drag; commit those immediately.
                                if (!_dragging) controller.commitSeek(value);
                              }
                            : null,
                        onChangeEnd: active
                            ? (value) {
                                _dragging = false;
                                if (_cancelled) {
                                  _cancelled = false;
                                  return;
                                }
                                controller.commitSeek(value);
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
