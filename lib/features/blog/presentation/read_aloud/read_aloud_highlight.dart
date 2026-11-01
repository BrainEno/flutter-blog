import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Split only the affected visible leaf; nesting, link recognizers, semantics
/// and the original article text are retained. Offsets use UTF-16 units.
TextSpan readAloudTextSpan({
  required String text,
  required SpeechTextRange? range,
  required ReadAloudHighlight? highlight,
  GestureRecognizer? recognizer,
  TextDecoration? existingDecoration,
}) {
  if (range == null || highlight == null || text.isEmpty) {
    return TextSpan(text: text, recognizer: recognizer);
  }
  final start = (highlight.start - range.start).clamp(0, text.length);
  final end = (highlight.end - range.start).clamp(0, text.length);
  if (end <= start) return TextSpan(text: text, recognizer: recognizer);
  return TextSpan(
    children: [
      if (start > 0)
        TextSpan(text: text.substring(0, start), recognizer: recognizer),
      TextSpan(
        text: text.substring(start, end),
        recognizer: recognizer,
        style: TextStyle(
          decoration: existingDecoration == null
              ? TextDecoration.underline
              : TextDecoration.combine([
                  existingDecoration,
                  TextDecoration.underline,
                ]),
          decorationColor: AppPalette.orange,
          decorationThickness: 2,
        ),
      ),
      if (end < text.length)
        TextSpan(text: text.substring(end), recognizer: recognizer),
    ],
  );
}
