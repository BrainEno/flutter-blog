import 'dart:math' as math;

import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

    return Tooltip(
      message: label,
      child: Semantics(
        toggled: isDarkMode,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              context.read<ThemeBloc>().add(
                ToggleTheme(systemBrightness: Theme.of(context).brightness),
              );
            },
            borderRadius: BorderRadius.circular(height / 2),
            // Keep the existing visual dimensions but expose a 48px target.
            child: SizedBox(
              width: math.max(48.0, width),
              height: math.max(48.0, height),
              child: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(height / 2),
                          color: isDarkMode
                              ? Colors.grey.shade800
                              : Colors.amber.shade600,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: width * 0.12,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: isDarkMode ? 0.3 : 1,
                          child: Icon(
                            Icons.wb_sunny,
                            size: height * 0.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Positioned(
                        right: width * 0.12,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: isDarkMode ? 1 : 0.3,
                          child: Icon(
                            Icons.nightlight_round,
                            size: height * 0.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        alignment: isDarkMode
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Container(
                            width: height - 6,
                            height: height - 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.surface,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
