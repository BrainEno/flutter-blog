import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:belog/core/theme/theme_bloc.dart';

class ThemeToggleButton extends StatelessWidget {
  /// You can override these to suit your layout
  final double width;
  final double height;

  const ThemeToggleButton({
    super.key,
    this.width = 60,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    // This is the resolved brightness even when following the system theme.
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          context.read<ThemeBloc>().add(ToggleTheme(
                systemBrightness: Theme.of(context).brightness,
              ));
        },
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background bar with shadow
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  color:
                      isDarkMode ? Colors.grey.shade800 : Colors.amber.shade600,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),

              // Sun icon (fades)
              Positioned(
                left: width * 0.12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isDarkMode ? 0.3 : 1.0,
                  child: Icon(
                    Icons.wb_sunny,
                    size: height * 0.6,
                    color: Colors.white,
                  ),
                ),
              ),

              // Moon icon (fades)
              Positioned(
                right: width * 0.12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isDarkMode ? 1.0 : 0.3,
                  child: Icon(
                    Icons.nightlight_round,
                    size: height * 0.6,
                    color: Colors.white,
                  ),
                ),
              ),

              // Sliding thumb
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                alignment:
                    isDarkMode ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    width: height - 6,
                    height: height - 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
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
    );
  }
}
