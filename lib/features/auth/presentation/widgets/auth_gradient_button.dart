import 'package:belog/core/theme/app_palette.dart'; // Import your color palette
import 'package:flutter/material.dart';

class AuthGradientButton extends StatelessWidget {
  final String buttonText;
  final VoidCallback onPressed;
  const AuthGradientButton({
    super.key,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppPalette.greenColor.withAlpha(
              (0.9 * 255).toInt(),
            ), // Slightly less opaque Spotify Green for start
            AppPalette.greenColor, // Full Spotify Green for end
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          stops: const [
            0.2,
            1.0,
          ], // Optional: Adjust stops for gradient distribution
        ),
        borderRadius: BorderRadius.circular(8), // Consistent rounded corners
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              Colors.transparent, // Keep button background transparent
          shadowColor: Colors.transparent, // Remove shadow
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppPalette
                .blackColor, // Ensure text is still readable on the gradient
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(buttonText),
      ),
    );
  }
}
