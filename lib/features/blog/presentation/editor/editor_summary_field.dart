import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// no-wave's limit on an article summary, in characters.
const int articleSummaryMaxLength = 2000;

/// The counter appears only this close to [articleSummaryMaxLength]: most
/// summaries are a sentence or two, and a running "38 / 2000" is noise.
const int _counterVisibleFrom = 1800;

/// The article's optional summary: the lines readers see under the title in
/// lists and when the article is shared.
///
/// Left empty, no-wave writes one from the body. The field only lays out the
/// text; the page decides what a write sends (an untouched summary keeps the
/// article's own).
class EditorSummaryField extends StatelessWidget {
  const EditorSummaryField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      key: const Key('editor-summary-field'),
      controller: controller,
      minLines: 2,
      maxLines: 6,
      maxLength: articleSummaryMaxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      buildCounter:
          (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) => currentLength < _counterVisibleFrom
          ? null
          : Text(
              l10n.editorSummaryCounter(currentLength, articleSummaryMaxLength),
            ),
      decoration: InputDecoration(
        labelText: l10n.editorSummaryLabel,
        helperText: l10n.editorSummaryHelper,
        helperMaxLines: 3,
        alignLabelWithHint: true,
      ),
    );
  }
}
