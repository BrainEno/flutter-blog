import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_sleep_timer.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_voice_picker.dart';
import 'package:belog/l10n/app_localizations.dart';
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
            ReadAloudNotice.sleepTimerFinished =>
              l10n.readAloudSleepTimerFinished,
            ReadAloudNotice.error => l10n.readAloudError,
          },
        };
        final scheme = Theme.of(context).colorScheme;
        final sleepTimerStatus = controller.hasSleepTimer
            ? l10n.readAloudSleepTimerActive(
                (controller.sleepTimerRemaining?.inMinutes ?? 0) + 1,
              )
            : l10n.readAloudSleepTimer;
        final hairline = scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha);
        // Buttons carry their own inset; starting them at zero puts the
        // glyph, not the hit area, on the column edge the text starts on.
        final flush = TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.medium),
          minimumSize: const Size(0, NoWaveSizes.tapTarget),
        );
        // A sheet of the darker paper rather than a band between two rules:
        // the player is a separate object laid on the page, and the article
        // around it keeps its quiet.
        return Container(
          key: const ValueKey('read-aloud-controls'),
          margin: const EdgeInsets.only(bottom: NoWaveSpacing.section),
          padding: const EdgeInsets.fromLTRB(
            NoWaveSpacing.medium,
            NoWaveSpacing.medium,
            NoWaveSpacing.medium,
            NoWaveSpacing.small,
          ),
          color: scheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // What it does now: one ink square to press, and beside it
              // what pressing does and where the voice is.
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('read-aloud-play'),
                    tooltip: label,
                    onPressed: controller.togglePlayback,
                    // The one solid object on the sheet: an ink square with
                    // the glyph knocked out, so the eye lands on "play".
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.onSurface,
                      foregroundColor: scheme.surface,
                      shape: const RoundedRectangleBorder(),
                      fixedSize: const Size.square(NoWaveSizes.tapTarget),
                      minimumSize: const Size.square(NoWaveSizes.tapTarget),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      controller.phase == ReadAloudPhase.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: NoWaveIconSize.action,
                    ),
                  ),
                  const SizedBox(width: NoWaveSpacing.medium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The button already says this to a screen reader;
                        // the words are here for the eye, and a finger that
                        // lands on them rather than on the square.
                        ExcludeSemantics(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: controller.togglePlayback,
                            child: Text(
                              label,
                              style: NoWaveTypography.title(
                                context,
                                size: NoWaveTypeScale.sectionTitle,
                              ),
                            ),
                          ),
                        ),
                        Semantics(
                          liveRegion:
                              !active &&
                              controller.notice != ReadAloudNotice.hint,
                          child: Text(
                            caption,
                            style: NoWaveTypography.meta(context).copyWith(
                              color:
                                  controller.notice == ReadAloudNotice.error &&
                                      !active
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (active)
                    IconButton(
                      key: const ValueKey('read-aloud-stop'),
                      tooltip: l10n.readAloudStop,
                      onPressed: controller.stop,
                      color: scheme.onSurface,
                      icon: const Icon(Icons.stop),
                    ),
                ],
              ),
              // How it reads only matters once it is reading: before the
              // first press the sheet is one line, so the article starts
              // where the reader expects it, and the deck unfolds under the
              // square when the voice starts (and folds away on stop).
              AnimatedCrossFade(
                duration: NoWaveMotionPolicy.resolve(
                  context,
                  NoWaveMotion.slow,
                ),
                sizeCurve: NoWaveMotionPolicy.curve,
                alignment: AlignmentDirectional.topStart,
                crossFadeState: active
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox(
                  width: double.infinity,
                  height: NoWaveSpacing.small,
                ),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: NoWaveSpacing.small),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                        trackHeight: NoWaveSizes.accentRule,
                        trackShape: const _FlushTrack(),
                        activeTrackColor: scheme.onSurface,
                        inactiveTrackColor: hairline,
                        disabledActiveTrackColor: hairline,
                        disabledInactiveTrackColor: hairline,
                        thumbShape: const _SquareThumb(),
                        thumbColor: scheme.onSurface,
                        disabledThumbColor: hairline,
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: NoWaveSizes.seekThumb,
                        ),
                        overlayColor: scheme.onSurface.withAlpha(
                          NoWaveOpacity.dividerAlpha,
                        ),
                      ),
                      child: Tooltip(
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
                                      if (!_dragging)
                                        controller.commitSeek(value);
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
                    const SizedBox(height: NoWaveSpacing.xs),
                    // How it reads: quieter settings under the player.
                    Wrap(
                      spacing: NoWaveSpacing.medium,
                      runSpacing: NoWaveSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
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
                                // No underline: a form field's rule under one word
                                // in a row of quiet settings.
                                underline: const SizedBox.shrink(),
                                isDense: true,
                                iconSize: NoWaveIconSize.inline,
                                style: NoWaveTypography.meta(context).copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                                items: [
                                  for (final value
                                      in ReadAloudController.speeds)
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
                              onTap: () =>
                                  controller.setFollow(!controller.follow),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Checkbox(
                                    key: const ValueKey('read-aloud-follow'),
                                    // Ink, like the rest of the sheet: the accent
                                    // is kept for what answers a touch.
                                    activeColor: scheme.onSurface,
                                    checkColor: scheme.surface,
                                    value: controller.follow,
                                    onChanged: (value) =>
                                        controller.setFollow(value ?? false),
                                  ),
                                  Text(
                                    l10n.readAloudFollow,
                                    style: NoWaveTypography.meta(
                                      context,
                                    ).copyWith(color: scheme.onSurface),
                                  ),
                                  const SizedBox(width: NoWaveSpacing.small),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (controller.voiceChoices.isNotEmpty)
                          TextButton.icon(
                            key: const ValueKey('read-aloud-voice'),
                            style: flush,
                            onPressed: () =>
                                ReadAloudVoicePicker.show(context, controller),
                            icon: const Icon(
                              Icons.record_voice_over_outlined,
                              size: NoWaveIconSize.inline,
                            ),
                            label: Text(
                              l10n.readAloudVoice,
                              style: NoWaveTypography.meta(
                                context,
                              ).copyWith(color: scheme.onSurface),
                            ),
                          ),
                        Tooltip(
                          message: l10n.readAloudSleepTimerHint,
                          child: PopupMenuButton<ReadAloudSleepTimerOption>(
                            key: const ValueKey('read-aloud-sleep-timer'),
                            tooltip: l10n.readAloudSleepTimer,
                            onSelected: controller.setSleepTimer,
                            itemBuilder: (context) => [
                              for (final option
                                  in ReadAloudSleepTimerOption.values)
                                PopupMenuItem<ReadAloudSleepTimerOption>(
                                  value: option,
                                  child: Row(
                                    children: [
                                      Icon(
                                        option == controller.sleepTimerOption
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                      ),
                                      const SizedBox(
                                        width: NoWaveSpacing.small,
                                      ),
                                      Text(_sleepTimerLabel(l10n, option)),
                                    ],
                                  ),
                                ),
                            ],
                            // Keep the trigger icon-only: at 2× text the English
                            // countdown label is wider than a narrow phone. The
                            // localized status remains visible below and is also the
                            // semantic label, so compact layout never hides state.
                            child: Semantics(
                              label: sleepTimerStatus,
                              button: true,
                              child: ExcludeSemantics(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    NoWaveSpacing.small,
                                  ),
                                  child: Icon(
                                    Icons.timer_outlined,
                                    size: NoWaveIconSize.inline,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (controller.hasSleepTimer)
                      Padding(
                        padding: const EdgeInsets.only(top: NoWaveSpacing.xs),
                        child: Text(
                          sleepTimerStatus,
                          style: NoWaveTypography.meta(
                            context,
                          ).copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _sleepTimerLabel(
  AppLocalizations l10n,
  ReadAloudSleepTimerOption option,
) {
  return switch (option) {
    ReadAloudSleepTimerOption.off => l10n.readAloudSleepTimerOff,
    ReadAloudSleepTimerOption.fiveMinutes => l10n.readAloudSleepTimerFive,
    ReadAloudSleepTimerOption.tenMinutes => l10n.readAloudSleepTimerTen,
    ReadAloudSleepTimerOption.fifteenMinutes => l10n.readAloudSleepTimerFifteen,
    ReadAloudSleepTimerOption.thirtyMinutes => l10n.readAloudSleepTimerThirty,
  };
}

/// The seek track runs the width of the column, so the thumb's outer edge
/// at either end lines up with the text above and below instead of sitting
/// an overlay's width in.
class _FlushTrack extends RectangularSliderTrackShape {
  const _FlushTrack();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? NoWaveSizes.accentRule;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    const inset = NoWaveSizes.seekThumb / 2;
    return Rect.fromLTWH(
      offset.dx + inset,
      top,
      parentBox.size.width - 2 * inset,
      height,
    );
  }
}

/// A small square of ink for the seek thumb: the same square as the end
/// mark, rather than Material's round knob.
class _SquareThumb extends SliderComponentShape {
  const _SquareThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(NoWaveSizes.seekThumb);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation);
    if (color == null) return;
    context.canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: NoWaveSizes.seekThumb,
        height: NoWaveSizes.seekThumb,
      ),
      Paint()..color = color,
    );
  }
}
