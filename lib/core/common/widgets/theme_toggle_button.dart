import 'dart:math' as math;

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Switches the persisted theme, with a square native tap target and a
/// localized description of the next mode.
///
/// A plain glyph like the language button beside it: the outlined box it
/// used to wear made it the only framed control in any app bar. The moon
/// and the sun turn into each other instead, a quarter turn with a fade,
/// so the switch is felt without a frame to announce it.
class ThemeToggleButton extends StatelessWidget {
  final double width;
  final double height;

  const ThemeToggleButton({super.key, this.width = 48, this.height = 48});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final label = isDarkMode
        ? context.l10n.switchToLight
        : context.l10n.switchToDark;

    return Semantics(
      toggled: isDarkMode,
      child: IconButton(
        tooltip: label,
        style: IconButton.styleFrom(
          minimumSize: Size(math.max(48.0, width), math.max(48.0, height)),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          context.read<ThemeBloc>().add(
            ToggleTheme(systemBrightness: Theme.of(context).brightness),
          );
        },
        icon: AnimatedSwitcher(
          duration: NoWaveMotionPolicy.resolve(context, NoWaveMotion.slow),
          switchInCurve: NoWaveMotionPolicy.curve,
          switchOutCurve: NoWaveMotionPolicy.curve,
          transitionBuilder: (child, animation) => RotationTransition(
            turns: Tween<double>(begin: -0.25, end: 0).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            key: ValueKey(isDarkMode),
          ),
        ),
      ),
    );
  }
}
