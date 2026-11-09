import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_body_field.dart';
import 'package:belog/features/blog/presentation/editor/editor_category_selector.dart';
import 'package:belog/features/blog/presentation/editor/editor_cover_field.dart';
import 'package:belog/features/blog/presentation/editor/editor_tag_selector.dart';
import 'package:belog/features/blog/presentation/widgets/editor_field.dart';
import 'package:flutter/material.dart';

/// The scrollable editor form: draft notices, cover, tags, title and body.
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
    required this.image,
    this.imageBytes,
    required this.isNewImageSelected,
    required this.blog,
    required this.hasUnclaimedDrafts,
    this.resumedFromQueue = false,
    required this.autoSaveStatus,
    required this.onPickCover,
    required this.categories,
    required this.selectedCategoryIds,
    required this.categoriesLoading,
    required this.categoriesFailed,
    required this.onCategoriesChanged,
    required this.onRetryCategories,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final List<String> selectedTags;
  final ValueChanged<List<String>> onTagsChanged;
  final File? image;
  final Uint8List? imageBytes;
  final bool isNewImageSelected;
  final Blog? blog;
  final bool hasUnclaimedDrafts;

  /// The text came from a failed queue entry, so the page says what happens to
  /// that entry when this publish succeeds.
  final bool resumedFromQueue;
  final AutoSaveStatus autoSaveStatus;
  final VoidCallback onPickCover;
  final List<CategoryRef> categories;
  final List<String> selectedCategoryIds;
  final bool categoriesLoading;
  final bool categoriesFailed;
  final ValueChanged<List<String>> onCategoriesChanged;
  final VoidCallback onRetryCategories;

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
              AutoSaveBanner(status: autoSaveStatus),
              // Space between the buttons and the cover image.
              const SizedBox(height: NoWaveSpacing.large),
              EditorCoverField(
                blog: blog,
                image: image,
                imageBytes: imageBytes,
                isNewImageSelected: isNewImageSelected,
                onTap: onPickCover,
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
              const SizedBox(height: NoWaveSpacing.large),
              EditorField(
                controller: titleController,
                hintText: context.l10n.fieldTitleHint,
                contentType: BlogEditorContentType.title,
              ),
              const SizedBox(height: NoWaveSpacing.large),
              EditorBodyField(controller: contentController),
            ],
          ),
        ),
      ),
    );
  }
}
