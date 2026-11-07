import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/features/blog/presentation/widgets/editor_field.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:flutter/material.dart';

/// The markdown body with its edit/preview toggle (issue #17).
class EditorBodyField extends StatefulWidget {
  const EditorBodyField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<EditorBodyField> createState() => _EditorBodyFieldState();
}

class _EditorBodyFieldState extends State<EditorBodyField> {
  /// Markdown preview toggle for the body field.
  bool _previewMode = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            return SegmentedButton<bool>(
              direction: constraints.maxWidth / scale < 260
                  ? Axis.vertical
                  : Axis.horizontal,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.l10n.editorSegmentEdit),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(context.l10n.editorSegmentPreview),
                ),
              ],
              selected: {_previewMode},
              onSelectionChanged: (selection) =>
                  setState(() => _previewMode = selection.first),
            );
          },
        ),
        const SizedBox(height: NoWaveSpacing.medium),
        if (_previewMode) _buildPreview(context) else _buildEditor(context),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkMode
        ? AppPalette.mutedOnInk
        : AppPalette.mutedOnPaper;
    final text = widget.controller.text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NoWaveSpacing.small),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: text.trim().isEmpty
          ? Text(
              context.l10n.previewEmptyBody,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : MarkdownBody(markdown: text),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return EditorField(
      controller: widget.controller,
      hintText: context.l10n.fieldBodyHint,
      maxLines: null,
      expands: true,
      contentType: BlogEditorContentType.body,
    );
  }
}
