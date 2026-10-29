import 'dart:async';
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_pallete.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/data/datasources/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/presentation/blocs/bog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/editor_field.dart';
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
  String? imageUrl;
  DateTime? updatedAt;
  int _draftRequestVersion = 0;
  late final BlogDraftStore _draftStore;

  Timer? _autoSaveTimer;
  _AutoSaveStatus _autoSaveStatus = _AutoSaveStatus.idle;
  bool _draftsReady = false;
  bool _hasUnsavedEdits = false;
  bool _editedDuringPublish = false;
  bool _suppressDraftFlush = false;
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
    if (_suppressDraftFlush || !_hasUnsavedEdits || _isBlankDraft()) return;
    // Only edits made while a publish was uploading should survive it.
    if (_publishStartedAt != null && !_editedDuringPublish) return;
    final draft = _currentDraft();
    unawaited(
      _draftStore.save(draft).then((_) {}, onError: (_) {}),
    );
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
        showSnackBar(context, '已恢复草稿');
      } else if (choice == DraftRecoveryChoice.discard) {
        final deleted = await _draftStore.discardIfUnchanged(draft);
        if (mounted) {
          showSnackBar(context, deleted ? '草稿已丢弃' : '草稿已更改，请重新打开编辑器');
        }
      }
    } catch (_) {
      if (mounted) showSnackBar(context, '无法读取或处理草稿，请重试');
    } finally {
      _draftsReady = true;
    }
  }

  void selectImage() async {
    final pickedImage = await pickImage();
    if (pickedImage != null) {
      setState(() {
        image = pickedImage;
        isNewImageSelected = true;
      });
    }
  }

  void saveBlog() {
    _draftRequestVersion++;
    if (formKey.currentState!.validate() && selectedTags.isNotEmpty) {
      _publishStartedAt = DateTime.now();
      _editedDuringPublish = false;
      final posterId =
          (context.read<AppUserCubit>().state as AppUserLoggedIn).user.id;
      if (widget.blog == null && image != null) {
        context.read<BlogUploadBloc>().add(
          UploadBlogEvent(
            image: image!,
            title: titleController.text.trim(),
            content: contentController.text.trim(),
            posterId: posterId,
            tags: selectedTags,
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
          ),
        );
      }
    } else {
      showSnackBar(context, '请填写所有必填字段并上传封面图片');
    }
  }

  void deleteBlog() {
    _draftRequestVersion++;
    if (widget.blog != null) {
      context.read<BlogUploadBloc>().add(
        DeleteBlogEvent(blogId: widget.blog!.id),
      );
    } else {
      showSnackBar(context, '无法删除未保存的文章');
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
      if (mounted) showSnackBar(context, '草稿已保存');
    } catch (_) {
      if (mounted) showSnackBar(context, '草稿保存失败，请重试');
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
      backgroundColor: isDarkMode
          ? AppPallete.blackColor
          : AppPallete.lightBackground,
      appBar: AppBar(
        backgroundColor: isDarkMode
            ? AppPallete.blackColor
            : AppPallete.lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDarkMode ? AppPallete.whiteColor : AppPallete.lightBlack,
        ),
        title: Text(
          widget.blog == null ? '撰写新文章' : '编辑文章',
          style: TextStyle(
            color: isDarkMode ? AppPallete.whiteColor : AppPallete.lightBlack,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          ElevatedButton(
            onPressed: saveBlog,
            style: ElevatedButton.styleFrom(
              minimumSize: Size(60, 30),
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
            child: Text('发布'),
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
                case 'delete':
                  deleteBlog();
                  break;
                case 'cancel':
                  Navigator.of(context).pop();
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              if (widget.blog == null) {
                return [
                  PopupMenuItem<String>(
                    value: 'save',
                    child: Center(child: Text('保存并发布')),
                  ),
                  PopupMenuItem<String>(
                    value: 'save_draft',
                    child: Center(child: Text('保存草稿')),
                  ),
                ];
              } else {
                return [
                  PopupMenuItem<String>(
                    value: 'save',
                    child: Center(child: Text('保存更改')),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Center(child: Text('删除文章')),
                  ),
                  PopupMenuItem<String>(
                    value: 'save_draft',
                    child: Center(child: Text('保存草稿')),
                  ),
                  PopupMenuItem<String>(
                    value: 'cancel',
                    child: Center(child: Text('取消')),
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
            showSnackBar(context, state.error);
          } else if (state is BlogUploadSuccess) {
            if (widget.blog != null &&
                isNewImageSelected &&
                widget.blog!.imageUrl.isNotEmpty) {
              PaintingBinding.instance.imageCache.evict(
                Key(widget.blog!.imageUrl),
              );
            }
            showSnackBar(context, widget.blog == null ? '上传成功' : '更新成功');
            // Drop the drafts that were published; keep anything typed
            // during the upload (see _clearPublishedDrafts).
            _hasUnsavedEdits = _editedDuringPublish;
            unawaited(_clearPublishedDrafts());
            Navigator.of(context).pop(true);
          } else if (state is BlogDeleteSuccess) {
            showSnackBar(context, '删除成功');
            // The article is gone: clear all of its drafts and do not let
            // the dispose flush resurrect one.
            _suppressDraftFlush = true;
            unawaited(
              _draftStore
                  .deleteDraftsFor(widget.blog?.id)
                  .then((_) {}, onError: (_) {}),
            );
            Navigator.of(context).pop(true);
          }
        },
        builder: (context, state) {
          if (state is BlogUploadLoading || state is BlogDeleteLoading) {
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
                    GestureDetector(
                      onTap: selectImage,
                      child: image != null && isNewImageSelected
                          ? SizedBox(
                              height: 250,
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(image!, fit: BoxFit.cover),
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
                                  imageUrl:
                                      '${widget.blog!.imageUrl}?v=${widget.blog?.updatedAt.microsecondsSinceEpoch ?? ''}',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          : DottedBorder(
                              color: isDarkMode
                                  ? AppPallete.greyColorLight.withAlpha(
                                      (0.6 * 255).toInt(),
                                    )
                                  : AppPallete.lightBorder.withAlpha(
                                      (0.8 * 255).toInt(),
                                    ),
                              radius: const Radius.circular(12),
                              borderType: BorderType.RRect,
                              dashPattern: const [6, 3],
                              strokeCap: StrokeCap.round,
                              child: Container(
                                height: 250,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: isDarkMode
                                      ? AppPallete.blackColorLight.withAlpha(
                                          (0.3 * 255).toInt(),
                                        )
                                      : AppPallete.lightGrey.withAlpha(
                                          (0.15 * 255).toInt(),
                                        ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.image_outlined,
                                        size: 55,
                                        color: isDarkMode
                                            ? AppPallete.greyColor
                                            : AppPallete.lightGreyText,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '点击上传封面',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
                                          color: isDarkMode
                                              ? AppPallete.greyColor
                                              : AppPallete.lightGreyText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 36),
                    // ... rest of the existing Column children (tags, title, content) ...
                    Wrap(
                      spacing: 10.0,
                      runSpacing: 10.0,
                      children: ["诗歌", "小说", "原创", "其他"]
                          .map(
                            (e) => InputChip(
                              label: Text(
                                e,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: selectedTags.contains(e)
                                      ? AppPallete.whiteColor
                                      : isDarkMode
                                      ? AppPallete.whiteColor
                                      : AppPallete.lightBlack,
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
                                borderRadius: BorderRadius.circular(25),
                                side: BorderSide(
                                  color: isDarkMode
                                      ? AppPallete.greyColorLight.withAlpha(
                                          (0.7 * 255).toInt(),
                                        )
                                      : AppPallete.lightBorder.withAlpha(
                                          (0.7 * 255).toInt(),
                                        ),
                                ),
                              ),
                              backgroundColor: isDarkMode
                                  ? AppPallete.blackColorLight.withAlpha(
                                      (0.6 * 255).toInt(),
                                    )
                                  : AppPallete.lightGrey.withAlpha(
                                      (0.4 * 255).toInt(),
                                    ),
                              selectedColor: AppPallete.gradient1.withAlpha(
                                (0.9 * 255).toInt(),
                              ),
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: selectedTags.contains(e)
                                    ? AppPallete.blackColor
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
                      hintText: '标题',
                      contentType: BlogEditorContentType.title,
                    ),
                    const SizedBox(height: 30),
                    EditorField(
                      controller: contentController,
                      hintText: '正文',
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
        return const Text(
          '草稿自动保存中…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        );
      case _AutoSaveStatus.saved:
        return const Text(
          '草稿已自动保存',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        );
      case _AutoSaveStatus.failed:
        return const Text(
          '自动保存失败，请手动保存草稿',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.red),
        );
    }
  }
}
