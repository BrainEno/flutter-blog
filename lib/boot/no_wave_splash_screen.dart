import 'dart:async';
import 'dart:math' as math;

import 'package:belog/core/common/widgets/no_wave_wordmark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The cold-start curtain: six ink columns, a counter and a wordmark.
///
/// This is the native reading of no-wave's web `PageLoader`. The web page can
/// wait for fonts and images; an app must show something the moment the engine
/// has a surface, so the curtain is not a gate that blocks boot - it is drawn
/// *while* boot runs, and it lifts as soon as boot reports.
///
/// Three rules are load-bearing:
///
/// - **The counter is choreography, not progress.** It runs `000 → 088` on its
///   own clock and only jumps to `100` when boot actually finished. No request
///   measures it, so the UI must never claim it is a real percentage.
/// - **The curtain never becomes the app.** [onFinished] is what swaps in the
///   real tree; this widget only paints and reports.
/// - **Reduced motion means a still frame.** With animations disabled it shows
///   the first frame and calls [onFinished] as soon as boot is ready.
class NoWaveSplashScreen extends StatefulWidget {
  const NoWaveSplashScreen({
    super.key,
    required this.ready,
    required this.onFinished,
  });

  /// Completes when boot is done - successfully or not. A failure is the boot
  /// owner's problem to render; the curtain lifts either way.
  final Future<void> ready;

  /// Called once, after the last column has left the screen (immediately when
  /// animations are disabled).
  final VoidCallback onFinished;

  /// Whether the curtain already ran in this process.
  ///
  /// A hot reload or a rebuild must not replay a two-second introductory
  /// animation: the sequence belongs to the cold start, not to the widget
  /// lifecycle.
  static bool _hasPlayed = false;

  /// Lets a test observe the "already played" branch from a clean state.
  @visibleForTesting
  static void resetForTest() => _hasPlayed = false;

  @override
  State<NoWaveSplashScreen> createState() => _NoWaveSplashScreenState();
}

class _NoWaveSplashScreenState extends State<NoWaveSplashScreen>
    with TickerProviderStateMixin {
  /// The order the columns lift in.
  ///
  /// Deliberately not left-to-right: a sweep reads as a wipe transition, while
  /// an interleaved order reads as sheets being taken away. The values are
  /// positions, so the order stays identical on every boot.
  static const _liftOrder = [2, 0, 4, 1, 5, 3];

  /// Where the counter stops while boot is still running.
  static const _countUntilBoot = 88;

  /// How far the counter fades and grows before the curtain moves.
  static const _exitScale = 1.12;

  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: NoWaveMotion.counter,
  );

  late final AnimationController _wrapUp = AnimationController(
    vsync: this,
    duration: NoWaveMotion.counterFinish,
  );

  late final AnimationController _curtain = AnimationController(
    vsync: this,
    duration:
        NoWaveMotion.curtain +
        NoWaveMotion.stagger * (NoWaveSizes.splashColumns - 1),
  );

  Timer? _bail;
  DateTime? _startedAt;
  bool _started = false;
  bool _finishing = false;
  bool _finished = false;

  /// True when the sequence is replaced by a still frame: reduced motion, or a
  /// curtain that already played in this process.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start();
  }

  void _start() {
    _startedAt = DateTime.now();
    final reduceMotion = NoWaveMotionPolicy.reducesMotion(context);
    _still = reduceMotion || NoWaveSplashScreen._hasPlayed;

    // The bail is set in both modes: a boot that never reports must not leave
    // the user on a loading screen forever.
    _bail = Timer(NoWaveMotion.splashBail, _finish);

    if (_still) {
      unawaited(_awaitReady(immediate: true));
      return;
    }
    NoWaveSplashScreen._hasPlayed = true;
    _count.forward();
    unawaited(_awaitReady(immediate: false));
  }

  Future<void> _awaitReady({required bool immediate}) async {
    // A boot failure is rendered by the boot owner, not here; this screen only
    // needs to know that it no longer has to wait.
    await widget.ready.catchError((Object _) {});
    if (!mounted) return;
    if (immediate) {
      await _finish();
      return;
    }
    // Even an instant boot gets a complete curtain: anything shorter reads as
    // a flicker rather than as an opening.
    final elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
    final remaining = NoWaveMotion.minimumSplash - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing || !mounted) return;
    _finishing = true;
    _bail?.cancel();

    if (_still) {
      _reportFinished();
      return;
    }

    // 088 → 100, then the exit, then the columns.
    await _play(_count.forward);
    if (!mounted) return;
    await _play(_wrapUp.forward);
    if (!mounted) return;
    await _play(_curtain.forward);
    if (!mounted) return;
    _reportFinished();
  }

  /// Runs one controller pass, swallowing the cancellation a dispose causes.
  Future<void> _play(Future<void> Function() pass) async {
    try {
      await pass();
    } on TickerCanceled {
      // The widget went away mid-sequence; [mounted] guards the next step.
    }
  }

  void _reportFinished() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _bail?.cancel();
    _count.dispose();
    _wrapUp.dispose();
    _curtain.dispose();
    super.dispose();
  }

  /// Progress of one column, 0 → 1, with the stagger already applied.
  double _columnProgress(int column) {
    final order = _liftOrder.indexOf(column);
    final total = _curtain.duration?.inMilliseconds ?? 1;
    final start = (order * NoWaveMotion.stagger.inMilliseconds) / total;
    final end = start + NoWaveMotion.curtain.inMilliseconds / total;
    final curve = Interval(
      start,
      math.min(end, 1.0),
      curve: const Cubic(0.76, 0, 0.24, 1),
    );
    return curve.transform(_curtain.value);
  }

  /// The number on screen: eased towards 88, then the last stretch to 100.
  String _counterText() {
    final value = _wrapUp.isDismissed
        ? (_countUntilBoot * Curves.easeOut.transform(_count.value)).floor()
        : (_countUntilBoot +
                  (100 - _countUntilBoot) *
                      Curves.easeOut.transform(_wrapUp.value))
              .floor();
    return value.toString().padLeft(3, '0');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Semantics(
        liveRegion: true,
        label: l10n.splashSemanticsLoading,
        excludeSemantics: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppPalette.ink),
            _curtainColumns(),
            _centre(),
            _foot(l10n.splashBrandSubline),
            _progress(),
          ],
        ),
      ),
    );
  }

  /// Six ink sheets with a hairline seam, lifting in [_liftOrder].
  Widget _curtainColumns() {
    return AnimatedBuilder(
      animation: _curtain,
      builder: (context, _) {
        return Row(
          children: [
            for (var column = 0; column < NoWaveSizes.splashColumns; column++)
              Expanded(
                child: FractionalTranslation(
                  translation: Offset(0, -1.01 * _columnProgress(column)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.ink,
                      border: column == NoWaveSizes.splashColumns - 1
                          ? null
                          : const Border(
                              right: BorderSide(
                                color: AppPalette.curtainHairline,
                                width: NoWaveStroke.hairline,
                              ),
                            ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Counter and label, fading and growing as the columns prepare to lift.
  Widget _centre() {
    return Center(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: Listenable.merge([_count, _wrapUp]),
          builder: (context, _) {
            final exit = Curves.easeIn.transform(_wrapUp.value);
            return Opacity(
              opacity: 1 - exit,
              child: Transform.scale(
                scale: 1 + (_exitScale - 1) * exit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NoWaveSpacing.page,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The web's `min(30vw, 220px)`: a share of the width,
                      // capped. The FittedBox is the safety net for a doubled
                      // text scale - the glyphs shrink instead of clipping.
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final size = math.min(
                            constraints.maxWidth *
                                NoWaveSizes.splashCounterViewport,
                            NoWaveSizes.splashCounterMax,
                          );
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _counterText(),
                              style: NoWaveTypography.display(
                                context,
                                size: size,
                                color: AppPalette.paper,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: NoWaveSpacing.medium),
                      Text(
                        context.l10n.splashLoading,
                        textAlign: TextAlign.center,
                        style: NoWaveTypography.metaLabel(
                          context,
                          color: AppPalette.mutedOnInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Wordmark and its Chinese subline, bottom left inside the safe area.
  Widget _foot(String subline) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NoWaveWordmark(
                size: NoWaveSizes.splashWordmark,
                color: AppPalette.paper,
              ),
              const SizedBox(height: NoWaveSpacing.xs),
              Text(
                subline,
                style: NoWaveTypography.metaLabel(
                  context,
                  color: AppPalette.mutedOnInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A decorative segment: it marks the bottom edge, it does not measure
  /// anything.
  Widget _progress() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.large),
          child: SizedBox(
            width: NoWaveSizes.splashProgressLength,
            height: NoWaveSizes.splashProgress,
            child: const ColoredBox(color: AppPalette.orange),
          ),
        ),
      ),
    );
  }
}
