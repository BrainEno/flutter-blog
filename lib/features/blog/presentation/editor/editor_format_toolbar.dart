import 'dart:async';

import 'package:belog/core/design/components/no_wave_busy_mark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/features/blog/presentation/editor/markdown_editing.dart';
import 'package:flutter/material.dart';

/// The formatting row that rides above the keyboard while the body has focus,
/// with the same tools as the no-wave web editor: undo/redo, heading levels,
/// emphasis, quote, lists, code, link and image.
///
/// Every button only rewrites the body's Markdown through
/// `markdown_editing.dart`; nothing here talks to the server except
/// [onPickImage], which the owner supplies.
class EditorFormatToolbar extends StatefulWidget {
  const EditorFormatToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    this.undoController,
    this.onPickImage,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final UndoHistoryController? undoController;

  /// Picks and uploads a picture, answering its address, or null when the
  /// author cancelled or the upload failed (the owner reports that). Without
  /// it the image button is not offered.
  final Future<String?> Function()? onPickImage;

  @override
  State<EditorFormatToolbar> createState() => _EditorFormatToolbarState();
}

class _EditorFormatToolbarState extends State<EditorFormatToolbar> {
  bool _uploading = false;

  void _apply(TextEditingValue Function(TextEditingValue value) edit) {
    final controller = widget.controller;
    controller.value = edit(controller.value);
    final focus = widget.focusNode;
    if (focus != null && !focus.hasFocus) focus.requestFocus();
  }

  Future<void> _insertLink() async {
    final value = widget.controller.value;
    final selection = value.selection;
    final hasWords =
        selection.isValid &&
        !selection.isCollapsed &&
        selection.textInside(value.text).trim().isNotEmpty;
    final link = await showDialog<_LinkChoice>(
      context: context,
      builder: (_) => _LinkDialog(askForWords: !hasWords),
    );
    if (link == null || !mounted) return;
    _apply((current) => insertLink(current, link.url, label: link.words));
  }

  Future<void> _insertImage() async {
    final pick = widget.onPickImage;
    if (pick == null || _uploading) return;
    setState(() => _uploading = true);
    String? url;
    try {
      url = await pick();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    if (url == null || !mounted) return;
    final address = url;
    _apply((current) => insertImage(current, address));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final undo = widget.undoController;
    final tools = <Widget>[
      if (undo != null)
        ValueListenableBuilder<UndoHistoryValue>(
          valueListenable: undo,
          builder: (context, history, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('editor-tool-undo'),
                tooltip: l10n.editorToolUndo,
                icon: const Icon(Icons.undo),
                onPressed: history.canUndo ? undo.undo : null,
              ),
              IconButton(
                key: const Key('editor-tool-redo'),
                tooltip: l10n.editorToolRedo,
                icon: const Icon(Icons.redo),
                onPressed: history.canRedo ? undo.redo : null,
              ),
            ],
          ),
        ),
      if (undo != null) const _ToolDivider(),
      _Tool(
        id: 'heading',
        tooltip: l10n.editorToolHeading,
        icon: Icons.title,
        onPressed: () => _apply(cycleHeading),
      ),
      _Tool(
        id: 'bold',
        tooltip: l10n.editorToolBold,
        icon: Icons.format_bold,
        onPressed: () =>
            _apply((value) => toggleInlineMark(value, MarkdownInlineMark.bold)),
      ),
      _Tool(
        id: 'italic',
        tooltip: l10n.editorToolItalic,
        icon: Icons.format_italic,
        onPressed: () => _apply(
          (value) => toggleInlineMark(value, MarkdownInlineMark.italic),
        ),
      ),
      _Tool(
        id: 'strikethrough',
        tooltip: l10n.editorToolStrikethrough,
        icon: Icons.format_strikethrough,
        onPressed: () => _apply(
          (value) => toggleInlineMark(value, MarkdownInlineMark.strikethrough),
        ),
      ),
      _Tool(
        id: 'underline',
        tooltip: l10n.editorToolUnderline,
        icon: Icons.format_underlined,
        onPressed: () => _apply(
          (value) => toggleInlineMark(value, MarkdownInlineMark.underline),
        ),
      ),
      const _ToolDivider(),
      _Tool(
        id: 'quote',
        tooltip: l10n.editorToolQuote,
        icon: Icons.format_quote,
        onPressed: () =>
            _apply((value) => toggleLineStyle(value, MarkdownLineStyle.quote)),
      ),
      _Tool(
        id: 'bullet',
        tooltip: l10n.editorToolBulletList,
        icon: Icons.format_list_bulleted,
        onPressed: () =>
            _apply((value) => toggleLineStyle(value, MarkdownLineStyle.bullet)),
      ),
      _Tool(
        id: 'ordered',
        tooltip: l10n.editorToolOrderedList,
        icon: Icons.format_list_numbered,
        onPressed: () => _apply(
          (value) => toggleLineStyle(value, MarkdownLineStyle.ordered),
        ),
      ),
      _Tool(
        id: 'code',
        tooltip: l10n.editorToolInlineCode,
        icon: Icons.code,
        onPressed: () =>
            _apply((value) => toggleInlineMark(value, MarkdownInlineMark.code)),
      ),
      _Tool(
        id: 'code-block',
        tooltip: l10n.editorToolCodeBlock,
        icon: Icons.data_object,
        onPressed: () => _apply(insertCodeBlock),
      ),
      const _ToolDivider(),
      _Tool(
        id: 'link',
        tooltip: l10n.editorToolLink,
        icon: Icons.link,
        onPressed: () => unawaited(_insertLink()),
      ),
      if (widget.onPickImage != null)
        _uploading
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NoWaveSpacing.medium,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: NoWaveBusyMark(
                    size: NoWaveIconSize.action,
                    semanticsLabel: l10n.editorImageUploading,
                  ),
                ),
              )
            : _Tool(
                id: 'image',
                tooltip: l10n.editorToolImage,
                icon: Icons.image_outlined,
                onPressed: () => unawaited(_insertImage()),
              ),
    ];
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const Key('editor-format-toolbar'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: NoWaveSpacing.xs,
                ),
                child: Row(children: tools),
              ),
            ),
            if (widget.focusNode case final FocusNode focus)
              IconButton(
                key: const Key('editor-tool-done'),
                tooltip: l10n.editorToolDone,
                icon: const Icon(Icons.keyboard_hide_outlined),
                onPressed: focus.unfocus,
              ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key('editor-tool-$id'),
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NoWaveSpacing.large,
      child: VerticalDivider(
        width: NoWaveSpacing.medium,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _LinkChoice {
  const _LinkChoice(this.url, this.words);
  final String url;
  final String words;
}

/// Asks for the address (and the words, when none were selected). Only an
/// address no-wave will accept can be inserted.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.askForWords});

  final bool askForWords;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _url = TextEditingController();
  final _words = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _url.dispose();
    _words.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (!isValidArticleResourceUrl(url) || url.startsWith('/')) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(_LinkChoice(url, _words.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.editorLinkDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.askForWords)
            TextField(
              key: const Key('editor-link-words'),
              controller: _words,
              decoration: InputDecoration(labelText: l10n.editorLinkTextLabel),
              textInputAction: TextInputAction.next,
            ),
          TextField(
            key: const Key('editor-link-url'),
            controller: _url,
            autofocus: !widget.askForWords,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.editorLinkUrlLabel,
              hintText: 'https://',
              errorText: _showError ? l10n.editorLinkInvalid : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          key: const Key('editor-link-insert'),
          onPressed: _submit,
          child: Text(l10n.editorLinkInsert),
        ),
      ],
    );
  }
}
