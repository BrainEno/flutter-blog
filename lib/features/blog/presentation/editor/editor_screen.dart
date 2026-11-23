import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart' show AppPalette;
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/editor_app_bar.dart';
import 'package:belog/features/blog/presentation/editor/editor_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Presentation of a coordinator-owned editor. This widget does not create
/// controllers, access stores, dispatch events or decide whether a session is
/// current. All user and upload-state effects are delegated to the owner.
class EditorScreen extends StatelessWidget {
  const EditorScreen({
    super.key,
    required this.isCurrentEditor,
    required this.notionApplyStarted,
    required this.isEditing,
    required this.form,
    required this.onPublish,
    required this.onSaveDraft,
    required this.onCancel,
    required this.onImportNotion,
    required this.onExportNotion,
    required this.onUploadState,
    this.toolbar,
    this.bodyFocusNode,
    this.focusMode = false,
    this.onToggleFocusMode,
    this.onSaveServerDraft,
    this.isPublishedArticle = false,
  }) : assert(!isCurrentEditor || form != null);

  final bool isCurrentEditor;
  final bool notionApplyStarted;
  final bool isEditing;
  final EditorForm? form;
  final VoidCallback onPublish;
  final VoidCallback onSaveDraft;
  final VoidCallback onCancel;
  final VoidCallback onImportNotion;
  final VoidCallback? onExportNotion;
  final void Function(BuildContext, BlogUploadState) onUploadState;

  /// The format toolbar. It rides above the keyboard while [bodyFocusNode]
  /// has focus and is gone otherwise, so the title and settings stay calm.
  final Widget? toolbar;
  final FocusNode? bodyFocusNode;

  /// Whether the form shows only the writing; null [onToggleFocusMode] hides
  /// the switch.
  final bool focusMode;
  final VoidCallback? onToggleFocusMode;

  /// Stores the article on the server unpublished; null hides the entry.
  final VoidCallback? onSaveServerDraft;

  /// Whether the edited article is already public, so the draft entry
  /// reads as taking it back rather than keeping it private.
  final bool isPublishedArticle;

  @override
  Widget build(BuildContext context) {
    if (!isCurrentEditor) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(NoWaveSpacing.large),
            child: Text(
              notionApplyStarted
                  ? context.l10n.notionImportSessionChanged
                  : context.l10n.editorSessionChanged,
            ),
          ),
        ),
      );
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? AppPalette.ink : AppPalette.paper,
      appBar: EditorAppBar(
        isEditing: isEditing,
        onPublish: onPublish,
        onSaveDraft: onSaveDraft,
        onCancel: onCancel,
        onImportNotion: onImportNotion,
        onExportNotion: onExportNotion,
        focusMode: focusMode,
        onToggleFocusMode: onToggleFocusMode,
        onSaveServerDraft: onSaveServerDraft,
        isPublishedArticle: isPublishedArticle,
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocConsumer<BlogUploadBloc, BlogUploadState>(
              listener: onUploadState,
              builder: (context, state) {
                if (state is BlogUploadLoading) {
                  return const Center(child: NoWaveLoadingLabel());
                }
                return form!;
              },
            ),
          ),
          if ((toolbar, bodyFocusNode) case (
            final Widget tools,
            final FocusNode focus,
          ))
            ListenableBuilder(
              listenable: focus,
              builder: (context, _) => focus.hasFocus
                  // Part of the body field's tap region: pressing a tool
                  // must not count as tapping outside and close the keyboard.
                  ? TextFieldTapRegion(child: tools)
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
