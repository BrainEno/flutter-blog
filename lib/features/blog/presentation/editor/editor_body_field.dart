import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/features/blog/presentation/editor/markdown_editing.dart';
import 'package:belog/features/blog/presentation/widgets/editor_field.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:flutter/material.dart';

/// The Markdown body with its edit/preview toggle (issue #17), a live word
/// count and reading time, and Enter continuing lists and quotes.
///
/// The field grows with the text - the form scrolls, not a small box inside
/// it - so a long piece reads as one page while it is being written.
class EditorBodyField extends StatefulWidget {
  const EditorBodyField({
    super.key,
    required this.controller,
    this.focusNode,
    this.undoController,
  });

  final TextEditingController controller;

  /// Shared with the format toolbar, which only shows while the body has
  /// focus, and with the title, whose Enter key moves here.
  final FocusNode? focusNode;
  final UndoHistoryController? undoController;

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
        const SizedBox(height: NoWaveSpacing.small),
        if (_previewMode) _buildPreview(context) else _buildEditor(context),
        const SizedBox(height: NoWaveSpacing.small),
        _WritingStats(controller: widget.controller),
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
        borderRadius: BorderRadius.circular(NoWaveRadius.surface),
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
      key: const Key('editor-body-field'),
      controller: widget.controller,
      hintText: context.l10n.fieldBodyHint,
      placeholder: context.l10n.editorBodyPlaceholder,
      contentType: BlogEditorContentType.body,
      grows: true,
      minLines: 12,
      focusNode: widget.focusNode,
      undoController: widget.undoController,
      inputFormatters: const [MarkdownContinuationFormatter()],
    );
  }
}

/// "1,204 字 · 约 5 分钟": how far the piece has come, updated as it is typed.
class _WritingStats extends StatelessWidget {
  const _WritingStats({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = controller.text;
        final words = countArticleWords(text);
        final label = words == 0
            ? l10n.editorWordCount(0)
            : '${l10n.editorWordCount(words)} \u00b7 '
                  '${calculateReadingTime(l10n, text)}';
        return Text(
          label,
          key: const Key('editor-word-count'),
          textAlign: TextAlign.end,
          style: style,
        );
      },
    );
  }
}
