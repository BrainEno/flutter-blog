import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A validated auth field which inherits colors and shape from the app theme.
class AuthField extends StatelessWidget {
  final String hintText;
  final bool isObscureText;
  final TextEditingController controller;
  final IconData? prefixIcon;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final Color? borderColor;
  final Color? focusedBorderColor;
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
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: color, width: width),
        );

    return TextFormField(
      controller: controller,
      obscureText: isObscureText,
      style: style,
      decoration: InputDecoration(
        labelText: hintText,
        hintText: hintText,
        hintStyle: hintStyle,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        enabledBorder: borderColor == null ? null : border(borderColor!),
        focusedBorder: focusedBorderColor == null
            ? null
            : border(focusedBorderColor!, width: 2),
      ),
      validator: (value) => _effectiveValidator(context.l10n, value),
    );
  }

  String? _effectiveValidator(AppLocalizations l10n, String? value) {
    if (validator != null) return validator!(value);
    return value == null || value.isEmpty
        ? l10n.fieldRequiredPrompt(hintText)
        : null;
  }
}
