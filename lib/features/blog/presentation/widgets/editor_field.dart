import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart'; // Shorthand for AppLocalizations
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum BlogEditorContentType {
  title,
  body,
  tag, // Example for potential tag input - can be extended
  other,
}

/// One borderless writing field: the article title in the serif, or the body
/// at the reader's size and line height, so a draft already reads like the
/// published piece.
class EditorField extends StatelessWidget {
  /// The field's name - read by screen readers and used in the "required"
  /// message. [placeholder] is the friendlier text shown while it is empty.
  final String hintText;
  final String? placeholder;
  final TextEditingController controller;
  final BlogEditorContentType contentType;
  final TextStyle? hintStyle;
  final TextStyle? textStyle;
  final int? maxLines;
  final int? minLines;
  final bool expands;

  /// Grow with the text instead of scrolling inside a capped box. The page
  /// around the field scrolls; a long article never hides in a small window.
  final bool grows;

  final FocusNode? focusNode;
  final UndoHistoryController? undoController;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const EditorField({
    super.key,
    required this.controller,
    required this.hintText,
    this.placeholder,
    this.contentType = BlogEditorContentType.body,
    this.hintStyle,
    this.textStyle,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.grows = false,
    this.focusNode,
    this.undoController,
    this.inputFormatters,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  bool get _isTitle => contentType == BlogEditorContentType.title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fontSize = _isTitle
        ? NoWaveTypeScale.dialogTitle
        : NoWaveTypeScale.articleBody;
    final family = _isTitle ? 'InstrumentSerif' : 'InterTight';
    final fallback = _isTitle ? NoWaveTypography.serifFallback : null;
    // Titles sit tight; body text gets the reader's generous leading.
    final lineHeight = _isTitle ? 1.3 : 1.75;

    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      undoController: undoController,
      autofocus: autofocus,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      textCapitalization: TextCapitalization.sentences,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return context.l10n.editorFieldRequiredPrompt(hintText);
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: placeholder ?? hintText,
        hintMaxLines: _isTitle ? 2 : 8,
        hintStyle:
            hintStyle ??
            TextStyle(
              fontSize: fontSize,
              height: lineHeight,
              fontWeight: _isTitle ? FontWeight.w500 : FontWeight.w300,
              fontFamily: family,
              fontFamilyFallback: fallback,
              color: scheme.onSurfaceVariant,
            ),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          vertical: _isTitle ? NoWaveSpacing.small : NoWaveSpacing.medium,
        ),
      ),
      style:
          textStyle ??
          TextStyle(
            fontSize: fontSize,
            height: lineHeight,
            fontWeight: _isTitle ? FontWeight.w600 : FontWeight.w400,
            fontFamily: family,
            fontFamilyFallback: fallback,
            color: scheme.onSurface,
          ),
      maxLines: grows ? null : maxLines,
      minLines: grows ? (minLines ?? 1) : minLines,
      expands: !grows && expands,
      // A title wraps but never breaks: Enter moves on to the body.
      keyboardType: _isTitle
          ? TextInputType.text
          : maxLines == 1 && !grows
          ? null
          : TextInputType.multiline,
      cursorColor: scheme.primary,
    );

    final labelled = Semantics(label: hintText, child: field);
    if (grows) return labelled;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final heightScale = scale < 1 ? 1.0 : scale;
    return Container(
      constraints: BoxConstraints(
        minHeight: 80 * heightScale,
        maxHeight: 300 * heightScale,
      ),
      padding: const EdgeInsets.symmetric(
        vertical: 2.0, // design-token-ok: the field hugs the text it holds
        horizontal: NoWaveSpacing.small,
      ),
      child: labelled,
    );
  }
}
