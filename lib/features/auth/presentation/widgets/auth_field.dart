import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A validated auth field: a labelled underline in ink, orange on focus.
class AuthField extends StatelessWidget {
  final String hintText;

  /// A standing rule shown under the line (for example a password's
  /// minimum length). It wraps instead of riding in the label, which is
  /// one line and would cut the rule off at a large text size.
  final String? helperText;
  final bool isObscureText;
  final TextEditingController controller;
  final IconData? prefixIcon;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool enabled;

  const AuthField({
    super.key,
    required this.hintText,
    required this.controller,
    this.helperText,
    this.isObscureText = false,
    this.prefixIcon,
    this.style,
    this.hintStyle,
    this.borderColor,
    this.focusedBorderColor,
    this.validator,
    this.keyboardType,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    UnderlineInputBorder line(Color color, {double? width}) =>
        UnderlineInputBorder(
          borderSide: BorderSide(
            color: color,
            width: width ?? NoWaveStroke.hairline,
          ),
        );

    // A line to write on, not a box: the same underline as the comment
    // composer, with the label set above the text once it has any. Focus
    // turns the line orange and thicker, the one place accent answers a
    // touch on this page.
    return TextFormField(
      controller: controller,
      obscureText: isObscureText,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      enabled: enabled,
      style: style ?? Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: hintText,
        hintStyle: hintStyle,
        helperText: helperText,
        // Rules and errors are sentences; at 2x text on a narrow phone one
        // line cuts them mid-word, so they may wrap.
        helperMaxLines: _messageMaxLines,
        errorMaxLines: _messageMaxLines,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          vertical: NoWaveSpacing.medium,
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: scheme.onSurface),
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        border: line(borderColor ?? scheme.onSurface),
        enabledBorder: line(borderColor ?? scheme.onSurface),
        disabledBorder: line(scheme.onSurfaceVariant),
        focusedBorder: line(
          focusedBorderColor ?? AppPalette.orange,
          width: NoWaveStroke.focus,
        ),
        errorBorder: line(scheme.error),
        focusedErrorBorder: line(scheme.error, width: NoWaveStroke.focus),
      ),
      validator: (value) => _effectiveValidator(context.l10n, value),
    );
  }

  static const _messageMaxLines = 4;

  String? _effectiveValidator(AppLocalizations l10n, String? value) {
    if (validator != null) return validator!(value);
    return value == null || value.isEmpty
        ? l10n.fieldRequiredPrompt(hintText)
        : null;
  }
}
