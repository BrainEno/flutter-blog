import 'package:flutter/material.dart';

/// Authentication action using the shared, accessible no-wave button theme.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.buttonText,
    required this.onPressed,
  });

  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(buttonText),
    );
  }
}
