import 'dart:math' as math;

import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Switches the persisted theme, with a square native tap target and a
/// localized description of the next mode.
class ThemeToggleButton extends StatelessWidget {
  final double width;
  final double height;

  const ThemeToggleButton({super.key, this.width = 60, this.height = 34});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final label = isDarkMode
        ? context.l10n.switchToLight
        : context.l10n.switchToDark;
    final outline = Theme.of(context).colorScheme.outline;

    return Semantics(
      toggled: isDarkMode,
      child: IconButton(
        tooltip: label,
        style: IconButton.styleFrom(
          minimumSize: Size(math.max(48.0, width), math.max(48.0, height)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: outline),
          ),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          context.read<ThemeBloc>().add(
            ToggleTheme(systemBrightness: Theme.of(context).brightness),
          );
        },
        icon: Icon(
          isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        ),
      ),
    );
  }
}
