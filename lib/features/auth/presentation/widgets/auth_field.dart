import 'package:belog/core/theme/app_palette.dart'; // Import your color palette
import 'package:flutter/material.dart';

class AuthField extends StatelessWidget {
  final String hintText;
  final bool isObscureText;
  final TextEditingController controller;
  final IconData? prefixIcon; // New: Optional prefix icon
  final TextStyle? style; // New: Optional text style
  final TextStyle? hintStyle; // New: Optional hint text style
  final Color? borderColor; // New: Optional border color
  final Color? focusedBorderColor; // New: Optional focused border color

  /// Optional extra validation. When null the field only requires
  /// non-empty input.
  final FormFieldValidator<String>? validator;

  const AuthField({
    super.key,
    required this.hintText,
    required this.controller,
    this.isObscureText = false,
    this.prefixIcon,
    this.style,
    this.hintStyle,
    this.borderColor,
    this.focusedBorderColor,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      autofocus: false,
      controller: controller,
      obscureText: isObscureText,
      style:
          style ??
          TextStyle(
            fontSize: 16,
            color: isDarkMode
                ? AppPalette
                      .whiteColor // White text in dark mode
                : AppPalette.lightBlack, // Black text in light mode
          ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle:
            hintStyle ??
            TextStyle(
              fontSize: 16,
              color: isDarkMode
                  ? AppPalette
                        .greyColor // Medium grey hint in dark mode
                  : AppPalette.lightGreyText, // Light grey hint in light mode
            ),
        prefixIcon: prefixIcon != null
            ? Icon(
                prefixIcon,
                color: isDarkMode
                    ? AppPalette
                          .greyColor // Medium grey icon in dark mode
                    : AppPalette.lightGreyText, // Light grey icon in light mode
              )
            : null,
        filled: true,
        fillColor: isDarkMode
            ? AppPalette
                  .greyColorDark // Dark grey background in dark mode
            : AppPalette.lightBackground, // White background in light mode
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16.0,
          horizontal: 20.0,
        ),
        border: _authFieldBorder(
          context,
          isDarkMode,
          borderColor,
        ), // Theme aware border
        enabledBorder: _authFieldBorder(
          context,
          isDarkMode,
          borderColor,
        ), // Theme aware enabled border
        focusedBorder: _authFieldFocusedBorder(
          context,
          focusedBorderColor,
        ), // Focused border remains gradient
        errorBorder: _authFieldErrorBorder(context), // Error border remains red
        focusedErrorBorder: _authFieldErrorBorder(
          context,
        ), // Focused error border remains red
      ),
      validator: _effectiveValidator,
    );
  }

  /// The custom [validator] when provided, otherwise a plain non-empty
  /// check.
  String? _effectiveValidator(String? value) {
    if (validator != null) {
      return validator!(value);
    }
    return value == null || value.isEmpty ? "请输入$hintText!" : null;
  }

  // Theme-aware border for the auth field
  OutlineInputBorder _authFieldBorder(
    BuildContext context,
    bool isDarkMode,
    Color? borderColor,
  ) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color:
            borderColor ??
            (isDarkMode
                ? AppPalette
                      .greyColorLight // Light grey border in dark mode
                : AppPalette.lightBorder), // Light border in light mode
      ),
    );
  }

  // Focused border remains Gradient independent of theme
  OutlineInputBorder _authFieldFocusedBorder(
    BuildContext context,
    Color? focusedBorderColor,
  ) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: focusedBorderColor ?? AppPalette.gradient2),
    );
  }

  // Error border remains red independent of theme
  OutlineInputBorder _authFieldErrorBorder(BuildContext context) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.redAccent),
    );
  }
}
