import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/domain/usecase/upload_article_image.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/user/presentation/widgets/user_media_picker_sheet.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/article_conflict_review_sheet.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_form.dart';
import 'package:belog/features/blog/presentation/editor/editor_format_toolbar.dart';
import 'package:belog/features/blog/presentation/editor/markdown_text_controller.dart';
import 'package:belog/features/blog/presentation/editor/editor_publish_intent.dart';
import 'package:belog/features/blog/presentation/widgets/draft_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:belog/features/blog/presentation/editor/editor_session_config.dart';
import 'package:belog/features/blog/presentation/editor/editor_screen.dart';
import 'package:belog/features/blog/presentation/editor/editor_session_fence.dart';
import 'package:belog/features/blog/presentation/editor/editor_notion_coordinator.dart';

part 'editor_session_cover.dart';
part 'editor_session_drafts.dart';
part 'editor_session_publish.dart';

/// Owns one Markdown editor's controllers, draft recovery, fenced async work,
/// publish intent and queue handoff. It delegates rendering to [EditorScreen].
/// The route wrapper passes dependencies through [config]; no network or storage
/// behavior is implemented by the presentation-only screen.
class EditorSessionCoordinator extends StatefulWidget {
  const EditorSessionCoordinator({super.key, required this.config});
  final EditorSessionConfig config;

  @override
  State<EditorSessionCoordinator> createState() =>
      _EditorSessionCoordinatorState();
}

class _EditorSessionCoordinatorState extends _EditorSessionBase
    with _EditorDraftLifecycle, _EditorCoverSelection, _EditorPublishFlow {
  @override
  void initState() {
    super.initState();
    _draftStore = widget.config.draftStore ?? GetIt.instance<BlogDraftStore>();
    _userCubit = context.read<AppUserCubit>();
    _session =
        widget.config.sessionIdentity ?? GetIt.instance<NowaveSessionManager>();
    _target = widget.config.blog ?? _queuedEditTarget();
    _expectedRevision =
        widget.config.queueEntry?.expectedRevision ??
        _target?.authoringRevision;
    final userState = _userCubit.state;
    _draftOwnerId = userState is AppUserLoggedIn ? userState.user.id : null;
    _editorGeneration = _session.sessionGeneration;
    _notion = EditorNotionCoordinator(
      identity: _session,
      userCubit: _userCubit,
      userId: _draftOwnerId,
      generation: _editorGeneration,
      isCurrent: () => _isCurrentEditor,
      importRepository: () => widget.config.notionImportRepository,
      exportRepository: () => widget.config.notionExportRepository,
    );
    _invalidated = !_matchesSession;
    _identitySubscription = _session.identityChanges.listen((_) {
      if (!_matchesSession) _invalidateEditor();
    });
    _userSubscription = _userCubit.stream.listen((_) {
      if (!_matchesSession) _invalidateEditor();
    });
    if (_target != null && !_invalidated) {
      titleController.text = _target.title;
      // The editor's Markdown: for a structured article, its blocks rendered
      // as the same text the web editor would show, not the reading text.
      contentController.text =
          _target.editableBody?.markdown ?? _target.content;
      selectedTags = List.from(_target.tags);
      // Show what the server says it is. Until the author touches the row this
      // is display only - the write omits `categoryIds` entirely.
      _selectedCategoryIds = List.of(_target.categoryIds);
    }
    final resumed = widget.config.queueEntry;
    if (resumed != null && !_invalidated) {
      _selectedCoverUrl = resumed.coverUrl;
      isNewImageSelected = resumed.coverUrl != null;
      // A resumed edit already filled the fields through [_target]; a resumed
      // create has no article behind it, so its text comes from the entry.
      if (_target == null) {
        titleController.text = resumed.title;
        contentController.text = resumed.content;
        selectedTags = List.from(resumed.tags);
      }
      // The entry carries whether the picker had been touched at queue time.
      final queuedCategoryIds = resumed.categoryIds;
      if (queuedCategoryIds != null) {
        _categoryTouched = true;
        _selectedCategoryIds = List.of(queuedCategoryIds);
      }
      unawaited(_loadQueuedCover(resumed));
    }
    // Attached after the initial text is in place, so pre-filling the
    // editors is not mistaken for an edit.
    titleController.addListener(_onEditorContentChanged);
    contentController.addListener(_onEditorContentChanged);
    if (!_invalidated) {
      loadDraft();
      _loadUnclaimedDraftNotice();
      unawaited(_loadCategories());
    }
  }

  void _invalidateEditor() {
    if (_invalidated) return;
    // An in-flight publish may have committed. Retain any pending text for
    // the original account, never in the replacement account's namespace.
    _autoSaveTimer?.cancel();
    _flushDraftOnDispose();
    _invalidated = true;
    _draftRequestVersion++;
    _dismissRecoveryDialog();
    _dismissMediaPicker();
    _notion.dismiss();
    if (mounted) setState(() {});
  }

  /// Rebuilds the article a queued edit targets, so a resumed edit updates
  /// that article instead of creating a new one.
  ///
  /// The entry also supplies a cover URL when the author selected or uploaded
  /// one before queueing. The update re-reads the real article before writing.
  Blog? _queuedEditTarget() {
    final entry = widget.config.queueEntry;
    final targetId = entry?.targetId;
    if (entry == null ||
        entry.kind != PublishQueueKind.edit ||
        (targetId ?? '').isEmpty) {
      return null;
    }
    return Blog(
      id: targetId!,
      // The repository still performs its metadata-preserving article read
      // before writing. The queue model only exists so the editor retains the
      // original condition and remains visibly in edit, not create, mode. Its
      // revision is held independently in [_expectedRevision], not in a data
      // model: presentation must not depend on the feature data layer.
      title: entry.title,
      content: entry.content,
      posterId: entry.userId,
      imageUrl: entry.coverUrl ?? '',
      tags: entry.tags,
      locale: entry.locale ?? '',
      updatedAt: entry.updatedAt,
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _flushDraftOnDispose();
    unawaited(_identitySubscription?.cancel());
    unawaited(_userSubscription?.cancel());
    _dismissRecoveryDialog();
    _dismissMediaPicker();
    _notion.dismiss();
    titleController.dispose();
    contentController.dispose();
    titleFocusNode.dispose();
    bodyFocusNode.dispose();
    bodyUndoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _isCurrentEditor;
    return EditorScreen(
      isCurrentEditor: current,
      notionApplyStarted: _notion.applyStarted,
      isEditing: _target != null,
      onPublish: saveBlog,
      onSaveDraft: saveDraft,
      onCancel: () => Navigator.of(context).pop(),
      onImportNotion: () => unawaited(_notion.openImport(context)),
      onExportNotion: _target == null
          ? null
          : () => unawaited(_notion.openExport(context, _target.id)),
      onUploadState: _onUploadState,
      bodyFocusNode: bodyFocusNode,
      toolbar: EditorFormatToolbar(
        controller: contentController,
        focusNode: bodyFocusNode,
        undoController: bodyUndoController,
        onPickImage: _bodyImageUploader == null ? null : _insertBodyImage,
      ),
      focusMode: _focusMode,
      onToggleFocusMode: () => setState(() => _focusMode = !_focusMode),
      form: !current
          ? null
          : EditorForm(
              formKey: formKey,
              titleController: titleController,
              contentController: contentController,
              selectedTags: selectedTags,
              onTagsChanged: _onTagsChanged,
              image: image,
              imageBytes: imageBytes,
              selectedCoverUrl: _selectedCoverUrl,
              isNewImageSelected: isNewImageSelected,
              blog: _target,
              hasUnclaimedDrafts: _hasUnclaimedDrafts,
              resumedFromQueue: widget.config.queueEntry != null,
              hasVersionConflict: _hasVersionConflict,
              onReviewVersionConflict: _reviewingVersionConflict
                  ? null
                  : () => unawaited(_reviewVersionConflict()),
              autoSaveStatus: _autoSaveStatus,
              onPickCover: selectImage,
              onChooseCoverFromLibrary: () =>
                  unawaited(selectCoverFromLibrary()),
              categories: _categories,
              selectedCategoryIds: _selectedCategoryIds,
              categoriesLoading: _categoriesLoading,
              categoriesFailed: _categoriesFailed,
              onCategoriesChanged: _onCategoriesChanged,
              onRetryCategories: () => unawaited(_loadCategories()),
              titleFocusNode: titleFocusNode,
              bodyFocusNode: bodyFocusNode,
              bodyUndoController: bodyUndoController,
              // A blank new piece starts in the title; an opened article or
              // a resumed entry keeps the reader where they are.
              autofocusTitle:
                  _target == null &&
                  widget.config.queueEntry == null &&
                  titleController.text.isEmpty,
              focusMode: _focusMode,
            ),
    );
  }

  UploadArticleImage? get _bodyImageUploader =>
      widget.config.uploadArticleImage ??
      (GetIt.instance.isRegistered<UploadArticleImage>()
          ? GetIt.instance<UploadArticleImage>()
          : null);

  /// Picks a picture and uploads it under this editor's account and session,
  /// answering its address for the toolbar to write into the body. A failure
  /// is reported here and answers null, leaving the text untouched.
  Future<String?> _insertBodyImage() async {
    final upload = _bodyImageUploader;
    final ownerId = _draftOwnerId;
    if (upload == null || ownerId == null || !_isCurrentEditor) return null;
    final PickedImage? picked;
    try {
      picked = await pickImage();
    } catch (_) {
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
      return null;
    }
    if (picked == null || !_isCurrentEditor) return null;
    final result = await upload(
      UploadArticleImageParams(
        image: picked.upload,
        sessionFence: NowaveSessionFence(
          userId: ownerId,
          generation: _editorGeneration,
        ),
      ),
    );
    if (!mounted || !_isCurrentEditor) return null;
    return result.fold<String?>((failure) {
      showSnackBar(context, localizedFailure(context.l10n, failure));
      return null;
    }, (url) => url);
  }

  void _onTagsChanged(List<String> tags) {
    setState(() => selectedTags = tags);
    _onEditorContentChanged();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesFailed = false;
    });
    try {
      // Read through the domain use case: the presentation layer must not
      // reach into the data layer, and the catalog is a public read either way.
      final useCase =
          widget.config.getCategories ?? GetIt.instance<GetCategories>();
      final result = await useCase(NoParams());
      if (!mounted || !_isCurrentEditor) return;
      setState(() {
        // A refused read is the same dead end as a thrown one: the row offers
        // a retry, and publishing stays possible.
        result.fold(
          (_) => _categoriesFailed = true,
          (categories) => _categories = categories,
        );
        _categoriesLoading = false;
      });
    } catch (_) {
      if (!mounted || !_isCurrentEditor) return;
      // A missing catalog never blocks publishing: the author can still send
      // the article, and the picker simply stays unavailable.
      setState(() {
        _categoriesLoading = false;
        _categoriesFailed = true;
      });
    }
  }

  void _onCategoriesChanged(List<String> categoryIds) {
    setState(() {
      _selectedCategoryIds = List.of(categoryIds);
      _categoryTouched = true;
    });
    _onEditorContentChanged();
  }
}

/// The editor's state, shared by the lifecycle pieces in the part files:
/// drafts ([_EditorDraftLifecycle]), cover ([_EditorCoverSelection]) and
/// publishing ([_EditorPublishFlow]). Every async step re-checks
/// [_isCurrentEditor] after each await - an account switch freezes the page.
abstract class _EditorSessionBase extends State<EditorSessionCoordinator> {
  final titleController = TextEditingController();

  /// Plain Markdown text, painted with live highlighting in the field.
  final contentController = MarkdownTextController();
  final titleFocusNode = FocusNode(debugLabel: 'editor title');
  final bodyFocusNode = FocusNode(debugLabel: 'editor body');
  final bodyUndoController = UndoHistoryController();

  /// Writing only: the cover, tags and categories are hidden.
  bool _focusMode = false;
  final formKey = GlobalKey<FormState>();
  List<String> selectedTags = [];

  /// The category catalog this editor was able to read, and how that read went.
  List<CategoryRef> _categories = const [];
  bool _categoriesLoading = false;
  bool _categoriesFailed = false;

  /// The categories the author has picked, in the order they were picked.
  ///
  /// Categories are editorial structure the desk cannot create, so the write
  /// only names these when the author actually touched the row:
  /// [_categoryTouched] is what separates "chose none" from "never looked",
  /// and only the first of those clears the article's categories on the server.
  /// The list starts as whatever the article already belongs to, including ids
  /// this page cannot name, so editing one chip does not drop the others.
  List<String> _selectedCategoryIds = const [];
  bool _categoryTouched = false;

  File? image;
  bool isNewImageSelected = false;
  String? _selectedCoverUrl;
  int _coverSelectionVersion = 0;

  /// The picked cover's bytes and MIME type; [image] only feeds the preview.
  ImageUpload? imageUpload;

  /// Cover bytes that have no picker file behind them (a resumed queue entry).
  Uint8List? imageBytes;
  int _draftRequestVersion = 0;
  late final BlogDraftStore _draftStore;
  late final AppUserCubit _userCubit;
  late final NowaveSessionIdentity _session;
  late final String? _draftOwnerId;
  late final int _editorGeneration;
  StreamSubscription<void>? _identitySubscription;
  StreamSubscription<AppUserState>? _userSubscription;
  NavigatorState? _recoveryNavigator;
  Route<DraftRecoveryChoice>? _recoveryRoute;
  bool _invalidated = false;
  bool _restoringDraft = false;
  bool _hasUnclaimedDrafts = false;

  Timer? _autoSaveTimer;
  AutoSaveStatus _autoSaveStatus = AutoSaveStatus.idle;
  bool _draftsReady = false;
  bool _hasUnsavedEdits = false;
  bool _editedDuringPublish = false;
  DateTime? _publishStartedAt;
  BlogDraft? _publishedDraftSnapshot;

  /// The immutable request snapshot currently in flight. It is the single
  /// source for BLoC dispatch and an offline queue retry, so typing after the
  /// button press cannot mutate what a failure stores.
  EditorPublishIntent? _publishIntent;

  NavigatorState? _mediaPickerNavigator;
  Route<dynamic>? _mediaPickerRoute;
  bool _mediaPickerOpen = false;
  late final EditorNotionCoordinator _notion;

  /// One key per publish intent (issue #23): a queued retry reuses it so the
  /// server replays the article instead of creating a second one. It is only
  /// cleared when this intent is finished - accepted, or handed to the queue.
  String? _publishIdempotencyKey;

  /// The article this editor updates, or null when it creates a new one.
  ///
  /// Normally [EditorSessionConfig.blog]. A failed *edit* resumed from the queue
  /// has no complete article to pass, so it is rebuilt from the entry: the id
  /// is what makes the update address the same article instead of publishing
  /// a second copy of it.
  late final Blog? _target;

  /// Condition captured from the article/draft that seeded the editor. It is
  /// only replaced after the author explicitly reviews a freshly fetched
  /// article in the conflict sheet; it is never refreshed silently at send.
  ArticleRevision? _expectedRevision;
  bool _hasVersionConflict = false;
  bool _reviewingVersionConflict = false;

  bool get _matchesSession {
    final userState = _userCubit.state;
    return EditorSessionFence(
      userId: _draftOwnerId,
      generation: _editorGeneration,
    ).matches(
      displayedUserId: userState is AppUserLoggedIn ? userState.user.id : null,
      activeUserId: _session.activeUserId,
      accessToken: _session.accessToken,
      currentGeneration: _session.sessionGeneration,
    );
  }

  bool get _isCurrentEditor => mounted && !_invalidated && _matchesSession;

  /// The queue is optional at this layer so the page can still be built (and
  /// tested) without it; without a queue a failure simply stays a failure.
  PublishQueueStore? get _queueStore {
    final injected = widget.config.publishQueueStore;
    if (injected != null) return injected;
    return GetIt.instance.isRegistered<PublishQueueStore>()
        ? GetIt.instance<PublishQueueStore>()
        : null;
  }

  PublishQueueDrainer? get _queueDrainer {
    final injected = widget.config.publishQueueDrainer;
    if (injected != null) return injected;
    return GetIt.instance.isRegistered<PublishQueueDrainer>()
        ? GetIt.instance<PublishQueueDrainer>()
        : null;
  }
}
