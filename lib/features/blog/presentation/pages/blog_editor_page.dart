import 'dart:async';
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/utils/cover_url.dart';
import 'package:belog/features/blog/presentation/widgets/editor_field.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/features/blog/presentation/widgets/draft_recovery_dialog.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Creates or edits an article.
///
/// The page is pushed as `/editor` (new article) or `/profile/editor` with
/// the article passed as `extra`. It pops with `true` when something was
/// published, updated or deleted, so the page below can refresh its list.
class BlogEditorPage extends StatefulWidget {
  final Blog? blog;
  final BlogDraftStore? draftStore;
  const BlogEditorPage({super.key, this.blog, this.draftStore});

  @override
  State<BlogEditorPage> createState() => _BlogEditorState();
}

/// Status of the background draft auto-save, shown as a thin banner.
enum _AutoSaveStatus { idle, saving, saved, failed }

class _BlogEditorState extends State<BlogEditorPage> {
  static const _kAutoSaveDelay = Duration(seconds: 2);

  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  List<String> selectedTags = [];
  File? image;
  bool isNewImageSelected = false;

  /// Markdown preview toggle for the body field (issue #17).
  bool _previewMode = false;

  /// MIME type of [image] when a new cover was picked; uploaded as the
  /// object's contentType.
  String? imageMimeType;
  int _draftRequestVersion = 0;
  late final BlogDraftStore _draftStore;

  Timer? _autoSaveTimer;
  _AutoSaveStatus _autoSaveStatus = _AutoSaveStatus.idle;
  bool _draftsReady = false;
  bool _hasUnsavedEdits = false;
  bool _editedDuringPublish = false;
  DateTime? _publishStartedAt;

  @override
  void initState() {
    super.initState();
    _draftStore = widget.draftStore ?? GetIt.instance<BlogDraftStore>();
    if (widget.blog != null) {
      titleController.text = widget.blog!.title;
      contentController.text = widget.blog!.content;
      selectedTags = List.from(widget.blog!.tags);
    }
    // Attached after the initial text is in place, so pre-filling the
    // editors is not mistaken for an edit.
    titleController.addListener(_onEditorContentChanged);
    contentController.addListener(_onEditorContentChanged);
    loadDraft();
  }

  /// Debounces the 2s background draft save. It only ever writes to the
  /// local draft store - it never publishes or network-posts anything.
  void _onEditorContentChanged() {
    if (!_draftsReady) return;
    _hasUnsavedEdits = true;
    if (_publishStartedAt != null) _editedDuringPublish = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_kAutoSaveDelay, _autoSaveDraft);
  }

  Future<void> _autoSaveDraft() async {
    if (!_isBlankDraft()) {
      final draft = _currentDraft();
      setState(() => _autoSaveStatus = _AutoSaveStatus.saving);
      try {
        await _draftStore.save(draft);
        // Edits made while this save was awaiting re-arm the auto-save
        // timer; only declare everything saved when none are pending.
        _hasUnsavedEdits = _autoSaveTimer?.isActive ?? false;
        if (mounted) setState(() => _autoSaveStatus = _AutoSaveStatus.saved);
      } catch (_) {
        if (mounted) setState(() => _autoSaveStatus = _AutoSaveStatus.failed);
      }
    }
  }

  bool _isBlankDraft() =>
      titleController.text.trim().isEmpty &&
      contentController.text.trim().isEmpty;

  BlogDraft _currentDraft() => BlogDraft(
    blogId: widget.blog?.id,
    title: titleController.text,
    content: contentController.text,
    tags: List.of(selectedTags),
    updatedAt: DateTime.now(),
  );

  /// Publish succeeded: drop this article's drafts that predate the publish
  /// request. Edits typed while the upload was in flight are newer and are
  /// deliberately kept.
  Future<void> _clearPublishedDrafts() async {
    final startedAt = _publishStartedAt;
    if (startedAt == null) return;
    try {
      await _draftStore.deleteDraftsFor(widget.blog?.id, olderThan: startedAt);
    } catch (_) {
      // Best-effort cleanup: a leftover draft is harmless.
    }
  }

  /// Best-effort save when the page is disposed mid-edit. Must not touch
  /// [context] - the widget is already unmounted.
  void _flushDraftOnDispose() {
    if (!_hasUnsavedEdits || _isBlankDraft()) return;
    // Only edits made while a publish was uploading should survive it.
    if (_publishStartedAt != null && !_editedDuringPublish) return;
    final draft = _currentDraft();
    unawaited(_draftStore.save(draft).then((_) {}, onError: (_) {}));
  }

  Future<void> loadDraft() async {
    final requestVersion = _draftRequestVersion;
    try {
      final draft = await _draftStore.load(widget.blog?.id);
      if (!mounted || requestVersion != _draftRequestVersion || draft == null) {
        return;
      }

      final choice = await showDraftRecoveryDialog(
        context,
        isOlderThanPublished:
            widget.blog != null &&
            widget.blog!.updatedAt.isAfter(draft.updatedAt),
      );
      if (!mounted || requestVersion != _draftRequestVersion) return;

      if (choice == DraftRecoveryChoice.restore) {
        setState(() {
          titleController.text = draft.title;
          contentController.text = draft.content;
          selectedTags = List.from(draft.tags);
        });
        if (mounted) showSnackBar(context, context.l10n.draftRestored);
      } else if (choice == DraftRecoveryChoice.discard) {
        final deleted = await _draftStore.discardIfUnchanged(draft);
        if (mounted) {
          showSnackBar(
            context,
            deleted ? context.l10n.draftDiscarded : context.l10n.draftChanged,
          );
        }
      }
    } catch (_) {
      if (mounted) showSnackBar(context, context.l10n.draftReadFailed);
    } finally {
      _draftsReady = true;
    }
  }

  void selectImage() async {
    try {
      final pickedImage = await pickImage();
      if (pickedImage != null) {
        setState(() {
          image = pickedImage.file;
          imageMimeType = pickedImage.mimeType;
          isNewImageSelected = true;
        });
      }
      // null = the user cancelled the picker: nothing to do.
    } catch (_) {
      // Picking failed (as opposed to being cancelled): surface it
      // instead of silently keeping the old cover.
      if (mounted) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
    }
  }

  void saveBlog() {
    _draftRequestVersion++;
    // Cover and tags are optional (issue #17): title and body are the
    // only required fields, and the backend already publishes text-only
    // articles as plain content blocks.
    if (formKey.currentState!.validate()) {
      _publishStartedAt = DateTime.now();
      _editedDuringPublish = false;
      final posterId =
          (context.read<AppUserCubit>().state as AppUserLoggedIn).user.id;
      if (widget.blog == null) {
        context.read<BlogUploadBloc>().add(
          UploadBlogEvent(
            image: image,
            title: titleController.text.trim(),
            content: contentController.text.trim(),
            posterId: posterId,
            tags: selectedTags,
            imageMimeType: imageMimeType,
          ),
        );
      } else if (widget.blog != null) {
        context.read<BlogUploadBloc>().add(
          UpdateBlogEvent(
            blogId: widget.blog!.id,
            image: isNewImageSelected ? image : null,
            title: titleController.text.trim(),
            content: contentController.text.trim(),
            tags: selectedTags,
            imageMimeType: isNewImageSelected ? imageMimeType : null,
          ),
        );
      }
    } else {
      showSnackBar(context, context.l10n.editorRequiredFields);
    }
  }

  Future<void> saveDraft() async {
    _draftRequestVersion++;
    // Take a snapshot before the first await: controllers may be edited or
    // disposed while the database transaction waits for its turn.
    final draft = BlogDraft(
      blogId: widget.blog?.id,
      title: titleController.text,
      content: contentController.text,
      tags: List.of(selectedTags),
      updatedAt: DateTime.now(),
    );
    try {
      await _draftStore.save(draft);
      // A pending auto-save timer means newer edits are waiting; let it run.
      _hasUnsavedEdits = _autoSaveTimer?.isActive ?? false;
      if (mounted) showSnackBar(context, context.l10n.draftSaved);
    } catch (_) {
      if (mounted) showSnackBar(context, context.l10n.draftSaveFailed);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _flushDraftOnDispose();
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? AppPalette.ink : AppPalette.paper,
      appBar: AppBar(
        backgroundColor: isDarkMode ? AppPalette.ink : AppPalette.paper,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDarkMode ? AppPalette.paper : AppPalette.ink,
        ),
        title: Text(
          widget.blog == null
              ? context.l10n.editorNewTitle
              : context.l10n.editorEditTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isDarkMode ? AppPalette.paper : AppPalette.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          ElevatedButton(
            onPressed: saveBlog,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(60, 48),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary, // Theme-based background
              foregroundColor: Theme.of(
                context,
              ).colorScheme.onPrimary, // Text color
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ), // Compact padding
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ), // Smaller, bold text
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20), // Rounded corners
              ),
              elevation: 0,
            ),
            child: Text(context.l10n.actionPublish),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'save':
                  saveBlog();
                  break;
                case 'save_draft':
                  saveDraft();
                  break;
                case 'cancel':
                  Navigator.of(context).pop();
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              // No delete entry here on purpose: deletion lives in "my
              // articles" (long-press) where the recycle bin entry sits
              // next to it.
              if (widget.blog == null) {
                return [
                  PopupMenuItem<String>(
                    value: 'save',
                    child: Center(child: Text(context.l10n.saveAndPublish)),
                  ),
                  PopupMenuItem<String>(
                    value: 'save_draft',
                    child: Center(child: Text(context.l10n.saveDraft)),
                  ),
                ];
              } else {
                return [
                  PopupMenuItem<String>(
                    value: 'save',
                    child: Center(child: Text(context.l10n.actionSaveChanges)),
                  ),
                  PopupMenuItem<String>(
                    value: 'save_draft',
                    child: Center(child: Text(context.l10n.saveDraft)),
                  ),
                  PopupMenuItem<String>(
                    value: 'cancel',
                    child: Center(child: Text(context.l10n.actionCancel)),
                  ),
                ];
              }
            },
          ),
        ],
      ),
      body: BlocConsumer<BlogUploadBloc, BlogUploadState>(
        listener: (context, state) {
          if (state is BlogUploadFailure) {
            showSnackBar(
              context,
              localizedFailure(context.l10n, state.failure),
            );
          } else if (state is BlogUploadSuccess) {
            // No manual imageCache eviction needed: covers are immutable
            // media URLs that change whenever a new cover is uploaded, so
            // the refreshed list/editor automatically fetches the new
            // asset.
            showSnackBar(
              context,
              widget.blog == null
                  ? context.l10n.uploadSuccess
                  : context.l10n.updateSuccess,
            );
            // Drop the drafts that were published; keep anything typed
            // during the upload (see _clearPublishedDrafts).
            _hasUnsavedEdits = _editedDuringPublish;
            unawaited(_clearPublishedDrafts());
            Navigator.of(context).pop(true);
          }
        },
        builder: (context, state) {
          if (state is BlogUploadLoading) {
            return const Loader();
          }
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AutoSaveBanner(status: _autoSaveStatus),
                    const SizedBox(
                      height: 20,
                    ), // Space between buttons and image
                    // Existing image container
                    Tooltip(
                      message: context.l10n.uploadCoverHint,
                      child: Semantics(
                        image: true,
                        label: context.l10n.coverImage,
                        child: InkWell(
                          onTap: selectImage,
                          child: image != null && isNewImageSelected
                              ? SizedBox(
                                  height: 250,
                                  width: double.infinity,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      image!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : widget.blog != null &&
                                    widget.blog!.imageUrl.isNotEmpty
                              ? SizedBox(
                                  height: 250,
                                  width: double.infinity,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      // Cover URLs are immutable and shared with the reader.
                                      imageUrl: coverUrlOf(widget.blog!),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : DottedBorder(
                                  color: isDarkMode
                                      ? AppPalette.mutedOnInk.withAlpha(
                                          (0.6 * 255).toInt(),
                                        )
                                      : AppPalette.mutedOnPaper.withAlpha(
                                          (0.8 * 255).toInt(),
                                        ),
                                  radius: const Radius.circular(12),
                                  borderType: BorderType.RRect,
                                  dashPattern: const [6, 3],
                                  strokeCap: StrokeCap.round,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 250,
                                    ),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: isDarkMode
                                          ? AppPalette.surfaceOnInk.withAlpha(
                                              (0.3 * 255).toInt(),
                                            )
                                          : AppPalette.surfaceOnPaper.withAlpha(
                                              (0.15 * 255).toInt(),
                                            ),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_outlined,
                                            size: 55,
                                            color: isDarkMode
                                                ? AppPalette.mutedOnInk
                                                : AppPalette.mutedOnPaper,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            context.l10n.uploadCoverHint,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w500,
                                              color: isDarkMode
                                                  ? AppPalette.mutedOnInk
                                                  : AppPalette.mutedOnPaper,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Wrap(
                      spacing: 10.0,
                      runSpacing: 10.0,
                      children: ["诗歌", "小说", "原创", "其他"]
                          .map(
                            (e) => InputChip(
                              label: Text(
                                localizedTag(context.l10n, e),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: selectedTags.contains(e)
                                      ? AppPalette.ink
                                      : isDarkMode
                                      ? AppPalette.paper
                                      : AppPalette.ink,
                                ),
                              ),
                              selected: selectedTags.contains(e),
                              elevation: 0,
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                                horizontal: 12.0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                                side: BorderSide(
                                  color: isDarkMode
                                      ? AppPalette.mutedOnInk.withAlpha(
                                          (0.7 * 255).toInt(),
                                        )
                                      : AppPalette.mutedOnPaper.withAlpha(
                                          (0.7 * 255).toInt(),
                                        ),
                                ),
                              ),
                              backgroundColor: isDarkMode
                                  ? AppPalette.surfaceOnInk.withAlpha(
                                      (0.6 * 255).toInt(),
                                    )
                                  : AppPalette.surfaceOnPaper.withAlpha(
                                      (0.4 * 255).toInt(),
                                    ),
                              selectedColor: AppPalette.orange,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: selectedTags.contains(e)
                                    ? AppPalette.ink
                                    : null,
                              ),
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    selectedTags.add(e);
                                  } else {
                                    selectedTags.remove(e);
                                  }
                                });
                                _onEditorContentChanged();
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 40),
                    EditorField(
                      controller: titleController,
                      hintText: context.l10n.fieldTitleHint,
                      contentType: BlogEditorContentType.title,
                    ),
                    const SizedBox(height: 30),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final scale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
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
                    const SizedBox(height: 12),
                    if (_previewMode)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDarkMode
                                ? AppPalette.mutedOnInk
                                : AppPalette.mutedOnPaper,
                          ),
                        ),
                        child: contentController.text.trim().isEmpty
                            ? Text(
                                context.l10n.previewEmptyBody,
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : MarkdownBody(markdown: contentController.text),
                      )
                    else
                      EditorField(
                        controller: contentController,
                        hintText: context.l10n.fieldBodyHint,
                        maxLines: null,
                        expands: true,
                        contentType: BlogEditorContentType.body,
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Thin status line for the background draft auto-save.
class _AutoSaveBanner extends StatelessWidget {
  final _AutoSaveStatus status;

  const _AutoSaveBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _AutoSaveStatus.idle:
        return const SizedBox.shrink();
      case _AutoSaveStatus.saving:
        return Text(
          context.l10n.autoSaveSaving,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        );
      case _AutoSaveStatus.saved:
        return Text(
          context.l10n.autoSaveSaved,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        );
      case _AutoSaveStatus.failed:
        return Text(
          context.l10n.autoSaveFailed,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        );
    }
  }
}
