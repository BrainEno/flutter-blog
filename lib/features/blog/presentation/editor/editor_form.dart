import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_body_field.dart';
import 'package:belog/features/blog/presentation/editor/editor_category_selector.dart';
import 'package:belog/features/blog/presentation/editor/editor_cover_field.dart';
import 'package:belog/features/blog/presentation/editor/editor_summary_field.dart';
import 'package:belog/features/blog/presentation/editor/editor_tag_selector.dart';
import 'package:belog/features/blog/presentation/widgets/editor_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The scrollable editor form: draft notices, cover, tags, title, body and
/// summary - or, in focus mode, only the notices, the title and the body.
///
/// It is deliberately stateless and side-effect free: the page owns the
/// controllers, the draft state machine and every decision, so this widget
/// only lays out the fields and reports user intent.
class EditorForm extends StatelessWidget {
  const EditorForm({
    super.key,
    required this.formKey,
    required this.titleController,
    required this.contentController,
    required this.selectedTags,
    required this.onTagsChanged,
    this.imageBytes,
    this.selectedCoverUrl,
    required this.isNewImageSelected,
    required this.blog,
    required this.hasUnclaimedDrafts,
    this.resumedFromQueue = false,
    this.hasVersionConflict = false,
    this.onReviewVersionConflict,
    required this.autoSaveStatus,
    required this.onPickCover,
    required this.onChooseCoverFromLibrary,
    this.onRecropCover,
    this.onClearCover,
    required this.categories,
    required this.selectedCategoryIds,
    required this.categoriesLoading,
    required this.categoriesFailed,
    required this.onCategoriesChanged,
    required this.onRetryCategories,
    this.titleFocusNode,
    this.bodyFocusNode,
    this.bodyUndoController,
    this.autofocusTitle = false,
    this.focusMode = false,
    this.summaryController,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final List<String> selectedTags;
  final ValueChanged<List<String>> onTagsChanged;
  final Uint8List? imageBytes;
  final String? selectedCoverUrl;
  final bool isNewImageSelected;
  final Blog? blog;
  final bool hasUnclaimedDrafts;

  /// The text came from a failed queue entry, so the page says what happens to
  /// that entry when this publish succeeds.
  final bool resumedFromQueue;

  /// A conditional update found a newer server work. The editor keeps the
  /// local draft visible and does not queue/retry it; this callback opens the
  /// explicit three-way review before the author can rebase its condition.
  final bool hasVersionConflict;
  final VoidCallback? onReviewVersionConflict;
  final AutoSaveStatus autoSaveStatus;
  final VoidCallback onPickCover;
  final VoidCallback onChooseCoverFromLibrary;

  /// Reopens the crop frame on the photo picked in this session; null when
  /// there is none (a library asset, the published cover, no cover).
  final VoidCallback? onRecropCover;

  /// Drops the cover chosen in this session; null when nothing was chosen.
  final VoidCallback? onClearCover;
  final List<CategoryRef> categories;
  final List<String> selectedCategoryIds;
  final bool categoriesLoading;
  final bool categoriesFailed;
  final ValueChanged<List<String>> onCategoriesChanged;
  final VoidCallback onRetryCategories;

  /// Owned by the page, so the format toolbar can follow the body's focus and
  /// drive its undo history.
  final FocusNode? titleFocusNode;
  final FocusNode? bodyFocusNode;
  final UndoHistoryController? bodyUndoController;

  /// A new, empty article starts with the caret in the title.
  final bool autofocusTitle;

  /// Writing only: the cover, tags and categories step aside until the author
  /// leaves focus mode. Notices that need an answer stay.
  final bool focusMode;

  /// The optional summary under the body; null leaves the field out.
  final TextEditingController? summaryController;

  String get _publishedCover =>
      blog?.editableBody?.coverUrl ?? blog?.imageUrl ?? '';

  bool get _hasCover =>
      (isNewImageSelected &&
          (imageBytes != null || (selectedCoverUrl ?? '').isNotEmpty)) ||
      _publishedCover.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NoWaveSpacing.large,
          vertical: NoWaveSpacing.large,
        ),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (resumedFromQueue)
                Padding(
                  padding: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
                  child: Text(
                    context.l10n.publishQueueResumedNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (hasUnclaimedDrafts)
                Padding(
                  padding: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(context.l10n.legacyDraftsNotice),
                  ),
                ),
              if (hasVersionConflict)
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
                    padding: const EdgeInsets.all(NoWaveSpacing.medium),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.articleConflictNoticeTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: NoWaveSpacing.small),
                        Text(context.l10n.articleConflictNoticeBody),
                        const SizedBox(height: NoWaveSpacing.small),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: onReviewVersionConflict,
                            icon: const Icon(Icons.compare_arrows_outlined),
                            label: Text(context.l10n.articleConflictReview),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // An unpublished article says so, and how it reaches readers.
              if (blog?.isDraft ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
                  child: NoWaveNotice(
                    key: const Key('editor-draft-notice'),
                    message: context.l10n.editorDraftArticleNotice,
                  ),
                ),
              AutoSaveBanner(status: autoSaveStatus),
              if (!focusMode) ...[
                // Space between the buttons and the cover image.
                const SizedBox(height: NoWaveSpacing.large),
                EditorCoverField(
                  blog: blog,
                  imageBytes: imageBytes,
                  selectedCoverUrl: selectedCoverUrl,
                  isNewImageSelected: isNewImageSelected,
                  onTap: onPickCover,
                ),
                EditorCoverActions(
                  hasCover: _hasCover,
                  hasPublishedCover: _publishedCover.isNotEmpty,
                  onPick: onPickCover,
                  onChooseFromLibrary: onChooseCoverFromLibrary,
                  onRecrop: onRecropCover,
                  onClear: onClearCover,
                ),
                const SizedBox(height: NoWaveSpacing.large),
                EditorTagSelector(
                  selectedTags: selectedTags,
                  onChanged: onTagsChanged,
                ),
                const SizedBox(height: NoWaveSpacing.large),
                EditorCategorySelector(
                  categories: categories,
                  selectedIds: selectedCategoryIds,
                  isLoading: categoriesLoading,
                  hasFailed: categoriesFailed,
                  onChanged: onCategoriesChanged,
                  onRetry: onRetryCategories,
                ),
              ],
              const SizedBox(height: NoWaveSpacing.large),
              EditorField(
                key: const Key('editor-title-field'),
                controller: titleController,
                hintText: context.l10n.fieldTitleHint,
                placeholder: context.l10n.editorTitlePlaceholder,
                contentType: BlogEditorContentType.title,
                grows: true,
                focusNode: titleFocusNode,
                autofocus: autofocusTitle,
                textInputAction: TextInputAction.next,
                // A title is one line: a pasted line break becomes a space.
                inputFormatters: [
                  FilteringTextInputFormatter.deny(
                    RegExp(r'[\r\n]+'),
                    replacementString: ' ',
                  ),
                ],
                onSubmitted: (_) => bodyFocusNode?.requestFocus(),
              ),
              const SizedBox(height: NoWaveSpacing.medium),
              EditorBodyField(
                controller: contentController,
                focusNode: bodyFocusNode,
                undoController: bodyUndoController,
              ),
              // Written once the piece is: below the body, out of the way in
              // focus mode.
              if (summaryController case final TextEditingController summary
                  when !focusMode) ...[
                const SizedBox(height: NoWaveSpacing.section),
                EditorSummaryField(controller: summary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
