import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';

/// Authentication action using the shared, accessible no-wave button theme.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.buttonText,
    required this.onPressed,
    this.isLoading = false,
  });

  final String buttonText;
  final VoidCallback onPressed;

  /// Keeps the form on screen while the request runs: the button holds its
  /// label and reports itself busy instead of the page swapping to a loader.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return NoWaveButton(
      label: buttonText,
      onPressed: onPressed,
      isLoading: isLoading,
      expand: true,
    );
  }
}
