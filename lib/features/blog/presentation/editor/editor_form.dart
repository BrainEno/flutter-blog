import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_body_field.dart';
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NoWaveSpacing.large,
          vertical: 20.0,
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
              const SizedBox(height: 20), // Space between buttons and image
              EditorCoverField(
                blog: blog,
                image: image,
                imageBytes: imageBytes,
                isNewImageSelected: isNewImageSelected,
                onTap: onPickCover,
              ),
              const SizedBox(height: 36),
              EditorTagSelector(
                selectedTags: selectedTags,
                onChanged: onTagsChanged,
              ),
              const SizedBox(height: 40),
              EditorField(
                controller: titleController,
                hintText: context.l10n.fieldTitleHint,
                contentType: BlogEditorContentType.title,
              ),
              const SizedBox(height: 30),
              EditorBodyField(controller: contentController),
            ],
          ),
        ),
      ),
    );
  }
}
