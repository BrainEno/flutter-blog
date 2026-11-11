import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// The popup menu entries of [EditorAppBar].
enum EditorMenuAction { publish, saveDraft, importNotion, exportNotion, cancel }

/// The editor's app bar: publish, save draft, and cancel when editing.
///
/// There is deliberately no delete entry: deletion lives in "my articles"
/// (long-press), where the recycle bin entry sits next to it.
class EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorAppBar({
    super.key,
    required this.isEditing,
    required this.onPublish,
    required this.onSaveDraft,
    required this.onCancel,
    required this.onImportNotion,
    this.onExportNotion,
  });

  /// True when an existing article is being edited, false for a new one.
  final bool isEditing;

  final VoidCallback onPublish;
  final VoidCallback onSaveDraft;
  final VoidCallback onCancel;
  final VoidCallback onImportNotion;
  final VoidCallback? onExportNotion;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final background = isDarkMode ? AppPalette.ink : AppPalette.paper;
    final foreground = isDarkMode ? AppPalette.paper : AppPalette.ink;
    return AppBar(
      backgroundColor: background,
      elevation: 0,
      iconTheme: IconThemeData(color: foreground),
      title: Text(
        isEditing ? context.l10n.editorEditTitle : context.l10n.editorNewTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: foreground, fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      actions: [
        // A square, full-weight primary action - the previous pill was the
        // last rounded button in the app. Its min size and padding now come
        // from the design tokens, so it sits in the 56pt toolbar like every
        // other NoWaveButton.
        NoWaveButton(label: context.l10n.actionPublish, onPressed: onPublish),
        PopupMenuButton<EditorMenuAction>(
          icon: const Icon(Icons.more_vert),
          onSelected: _onSelected,
          itemBuilder: _menuItems,
        ),
      ],
    );
  }

  void _onSelected(EditorMenuAction action) {
    switch (action) {
      case EditorMenuAction.publish:
        onPublish();
      case EditorMenuAction.saveDraft:
        onSaveDraft();
      case EditorMenuAction.importNotion:
        onImportNotion();
      case EditorMenuAction.exportNotion:
        onExportNotion?.call();
      case EditorMenuAction.cancel:
        onCancel();
    }
  }

  List<PopupMenuEntry<EditorMenuAction>> _menuItems(BuildContext context) {
    return [
      PopupMenuItem<EditorMenuAction>(
        value: EditorMenuAction.publish,
        child: Center(
          child: Text(
            isEditing
                ? context.l10n.actionSaveChanges
                : context.l10n.saveAndPublish,
          ),
        ),
      ),
      PopupMenuItem<EditorMenuAction>(
        value: EditorMenuAction.saveDraft,
        child: Center(child: Text(context.l10n.saveDraft)),
      ),
      PopupMenuItem<EditorMenuAction>(
        value: EditorMenuAction.importNotion,
        child: Center(child: Text(context.l10n.notionImportTitle)),
      ),
      if (onExportNotion != null)
        PopupMenuItem<EditorMenuAction>(
          value: EditorMenuAction.exportNotion,
          child: Center(child: Text(context.l10n.notionExportTitle)),
        ),
      if (isEditing)
        PopupMenuItem<EditorMenuAction>(
          value: EditorMenuAction.cancel,
          child: Center(child: Text(context.l10n.actionCancel)),
        ),
    ];
  }
}
