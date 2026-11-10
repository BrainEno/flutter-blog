import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/user/presentation/widgets/user_media_picker_sheet.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_app_bar.dart';
import 'package:belog/features/blog/presentation/editor/editor_form.dart';
import 'package:belog/features/blog/presentation/widgets/draft_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

/// Creates or edits an article.
///
/// The page is pushed as `/editor` (new article) or `/profile/editor` with
/// the article passed as `extra`. It pops with `true` when something was
/// published, updated or deleted, so the page below can refresh its list.
///
/// A [queueEntry] resumes the text and cover of a *failed* publish that never
/// reached the server. A failed *edit* also resumes in update mode: it names
/// the article it targets, so the text is written back to that article rather
/// than published as a second one. Either way the old entry is deleted once
/// this one has a successor - sent, or queued again.
class BlogEditorPage extends StatefulWidget {
  final Blog? blog;
  final PublishQueueEntry? queueEntry;
  final BlogDraftStore? draftStore;
  final NowaveSessionIdentity? sessionIdentity;
  final PublishQueueStore? publishQueueStore;
  final PublishQueueDrainer? publishQueueDrainer;

  /// The category catalog read. Injectable so a test can answer without a
  /// server; production resolves the shared, credential-free use case.
  final GetCategories? getCategories;

  /// The private media-library read. Injectable so picker tests can stay local.
  final GetUserMediaLibraryPage? getUserMediaLibraryPage;
  const BlogEditorPage({
    super.key,
    this.blog,
    this.queueEntry,
    this.draftStore,
    this.sessionIdentity,
    this.publishQueueStore,
    this.publishQueueDrainer,
    this.getCategories,
    this.getUserMediaLibraryPage,
  });

  @override
  State<BlogEditorPage> createState() => _BlogEditorState();
}

class _BlogEditorState extends State<BlogEditorPage> {
  static const _kAutoSaveDelay = Duration(seconds: 2);

  final titleController = TextEditingController();
  final contentController = TextEditingController();
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

  /// The cover sent with the current attempt, kept so a failure can be queued
  /// with the same bytes or reusable immutable media URL.
  ImageUpload? _publishImageSnapshot;
  String? _publishCoverUrlSnapshot;

  NavigatorState? _mediaPickerNavigator;
  Route<dynamic>? _mediaPickerRoute;
  bool _mediaPickerOpen = false;

  /// One key per publish intent (issue #23): a queued retry reuses it so the
  /// server replays the article instead of creating a second one. It is only
  /// cleared when this intent is finished - accepted, or handed to the queue.
  String? _publishIdempotencyKey;

  /// The article this editor updates, or null when it creates a new one.
  ///
  /// Normally [BlogEditorPage.blog]. A failed *edit* resumed from the queue
  /// has no complete article to pass, so it is rebuilt from the entry: the id
  /// is what makes the update address the same article instead of publishing
  /// a second copy of it.
  late final Blog? _target;

  @override
  void initState() {
    super.initState();
    _draftStore = widget.draftStore ?? GetIt.instance<BlogDraftStore>();
    _userCubit = context.read<AppUserCubit>();
    _session = widget.sessionIdentity ?? GetIt.instance<NowaveSessionManager>();
    _target = widget.blog ?? _queuedEditTarget();
    final userState = _userCubit.state;
    _draftOwnerId = userState is AppUserLoggedIn ? userState.user.id : null;
    _editorGeneration = _session.sessionGeneration;
    _invalidated = !_matchesSession;
    _identitySubscription = _session.identityChanges.listen((_) {
      if (!_matchesSession) _invalidateEditor();
    });
    _userSubscription = _userCubit.stream.listen((_) {
      if (!_matchesSession) _invalidateEditor();
    });
    if (_target != null && !_invalidated) {
      titleController.text = _target.title;
      contentController.text = _target.content;
      selectedTags = List.from(_target.tags);
      // Show what the server says it is. Until the author touches the row this
      // is display only - the write omits `categoryIds` entirely.
      _selectedCategoryIds = List.of(_target.categoryIds);
    }
    final resumed = widget.queueEntry;
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

  bool get _matchesSession {
    final owner = _draftOwnerId;
    final state = _userCubit.state;
    return owner != null &&
        owner.isNotEmpty &&
        owner == owner.trim() &&
        state is AppUserLoggedIn &&
        state.user.id == owner &&
        _session.activeUserId == owner &&
        _session.sessionGeneration == _editorGeneration &&
        !(_session.accessToken?.isEmpty ?? true);
  }

  bool get _isCurrentEditor => mounted && !_invalidated && _matchesSession;

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
    if (mounted) setState(() {});
  }

  void _dismissRecoveryDialog() {
    final route = _recoveryRoute;
    final navigator = _recoveryNavigator;
    _recoveryRoute = null;
    _recoveryNavigator = null;
    if (route == null || navigator == null) return;
    // Disposing the editor can happen while Navigator itself is locked.
    // Remove only our exact route after the current navigation frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _dismissMediaPicker() {
    if (!_mediaPickerOpen) return;
    final navigator = _mediaPickerNavigator;
    final route = _mediaPickerRoute;
    _mediaPickerOpen = false;
    _mediaPickerNavigator = null;
    // Keep the route slot until the pending modal future completes: its
    // builder may not have run yet when an identity change schedules removal.
    if (navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeRoute = route ?? _mediaPickerRoute;
      if (navigator.mounted && activeRoute != null && activeRoute.isActive) {
        navigator.removeRoute(activeRoute);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _loadUnclaimedDraftNotice() async {
    try {
      final found = await _draftStore.hasUnclaimedDrafts();
      if (_isCurrentEditor && found) setState(() => _hasUnclaimedDrafts = true);
    } catch (_) {
      // This notice is informational; a failed check never exposes a draft.
    }
  }

  /// Debounces the 2s background draft save. It only writes locally.
  void _onEditorContentChanged() {
    if (!_isCurrentEditor || _restoringDraft) return;
    _draftRequestVersion++;
    _hasUnsavedEdits = true;
    if (_publishStartedAt != null) _editedDuringPublish = true;
    if (_draftsReady) _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_kAutoSaveDelay, _autoSaveDraft);
  }

  Future<void> _autoSaveDraft() async {
    if (!_isCurrentEditor || _isBlankDraft()) return;
    final version = _draftRequestVersion;
    final draft = _currentDraft();
    setState(() => _autoSaveStatus = AutoSaveStatus.saving);
    try {
      await _draftStore.save(draft);
      if (!_isCurrentEditor) return;
      _hasUnsavedEdits = version != _draftRequestVersion;
      setState(() => _autoSaveStatus = AutoSaveStatus.saved);
    } catch (_) {
      if (_isCurrentEditor) {
        setState(() => _autoSaveStatus = AutoSaveStatus.failed);
      }
    }
  }

  bool _isBlankDraft() =>
      titleController.text.trim().isEmpty &&
      contentController.text.trim().isEmpty;

  BlogDraft _currentDraft() => BlogDraft(
    userId: _draftOwnerId!,
    blogId: _target?.id,
    title: titleController.text,
    content: contentController.text,
    tags: List.of(selectedTags),
    categoryIds: _categoryTouched ? List.of(_selectedCategoryIds) : null,
    updatedAt: DateTime.now(),
  );

  /// Only delete the exact locally saved snapshot that was published. A
  /// concurrent edit, another editor, or a clock adjustment must never make
  /// a later draft look old enough to delete.
  Future<void> _clearPublishedDraft() async {
    final snapshot = _publishedDraftSnapshot;
    if (snapshot == null || _editedDuringPublish) return;
    try {
      await _draftStore.discardIfUnchanged(snapshot);
    } catch (_) {
      // Best-effort cleanup: a leftover draft is safer than lost work.
    }
  }

  /// Best-effort save when the page is disposed mid-edit. Must not touch
  /// [context] - the widget is already unmounted.
  void _flushDraftOnDispose() {
    if (_draftOwnerId == null || !_hasUnsavedEdits || _isBlankDraft()) return;
    // A disposed or invalidated editor may have an unconfirmed publish. Keep
    // its text unless a success listener already marked those edits published.
    final draft = _currentDraft();
    _hasUnsavedEdits = false;
    unawaited(
      Future.sync(() => _draftStore.save(draft)).then((_) {}, onError: (_) {}),
    );
  }

  Future<void> loadDraft() async {
    final requestVersion = _draftRequestVersion;
    try {
      final draft = await _draftStore.load(_target?.id, userId: _draftOwnerId!);
      if (!mounted ||
          !_isCurrentEditor ||
          requestVersion != _draftRequestVersion ||
          draft == null ||
          draft.userId != _draftOwnerId ||
          draft.blogId != _target?.id) {
        return;
      }

      _recoveryNavigator = Navigator.of(context, rootNavigator: true);
      final choice = await showDraftRecoveryDialog(
        context,
        isOlderThanPublished:
            _target != null && _target.updatedAt.isAfter(draft.updatedAt),
        onRouteCreated: (route) => _recoveryRoute = route,
      );
      _recoveryRoute = null;
      if (!mounted ||
          !_isCurrentEditor ||
          requestVersion != _draftRequestVersion) {
        return;
      }

      if (choice == DraftRecoveryChoice.restore) {
        _restoringDraft = true;
        try {
          setState(() {
            titleController.text = draft.title;
            contentController.text = draft.content;
            selectedTags = List.from(draft.tags);
            final draftCategoryIds = draft.categoryIds;
            if (draftCategoryIds != null) {
              _categoryTouched = true;
              _selectedCategoryIds = List.of(draftCategoryIds);
            }
          });
        } finally {
          _restoringDraft = false;
        }
        showSnackBar(context, context.l10n.draftRestored);
      } else if (choice == DraftRecoveryChoice.discard) {
        final deleted = await _draftStore.discardIfUnchanged(draft);
        if (mounted && _isCurrentEditor) {
          showSnackBar(
            context,
            deleted ? context.l10n.draftDiscarded : context.l10n.draftChanged,
          );
        }
      }
    } catch (_) {
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.draftReadFailed);
      }
    } finally {
      if (_isCurrentEditor) {
        _draftsReady = true;
        if (_hasUnsavedEdits) _scheduleAutoSave();
      }
    }
  }

  void selectImage() async {
    if (!_isCurrentEditor) return;
    try {
      final pickedImage = await pickImage();
      if (!_isCurrentEditor) return;
      if (pickedImage != null) {
        _coverSelectionVersion++;
        setState(() {
          image = pickedImage.file;
          imageUpload = pickedImage.upload;
          imageBytes = null;
          _selectedCoverUrl = null;
          isNewImageSelected = true;
        });
      }
      // null = the user cancelled the picker: nothing to do.
    } catch (_) {
      // Picking failed (as opposed to being cancelled): surface it
      // instead of silently keeping the old cover.
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
    }
  }

  Future<void> selectCoverFromLibrary() async {
    if (!_isCurrentEditor) return;
    final getPage =
        widget.getUserMediaLibraryPage ??
        (GetIt.instance.isRegistered<GetUserMediaLibraryPage>()
            ? GetIt.instance<GetUserMediaLibraryPage>()
            : null);
    if (getPage == null) {
      showSnackBar(context, context.l10n.userMediaPickerLoadFailed);
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    _mediaPickerNavigator = navigator;
    _mediaPickerOpen = true;
    UserMediaAsset? selected;
    try {
      selected = await showModalBottomSheet<UserMediaAsset>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (sheetContext) {
          _mediaPickerRoute = ModalRoute.of(sheetContext);
          return UserMediaPickerSheet(
            getPage: getPage,
            sessionFence: NowaveSessionFence(
              userId: _draftOwnerId!,
              generation: _editorGeneration,
            ),
            sessionIdentity: _session,
          );
        },
      );
    } catch (_) {
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.userMediaPickerLoadFailed);
      }
    } finally {
      _mediaPickerOpen = false;
      _mediaPickerNavigator = null;
      _mediaPickerRoute = null;
    }

    final selectedAsset = selected;
    if (selectedAsset == null || !mounted || !_isCurrentEditor) return;
    _coverSelectionVersion++;
    setState(() {
      image = null;
      imageUpload = null;
      imageBytes = null;
      _selectedCoverUrl = selectedAsset.imageUrl;
      isNewImageSelected = true;
    });
  }

  /// The queue is optional at this layer so the page can still be built (and
  /// tested) without it; without a queue a failure simply stays a failure.
  PublishQueueStore? get _queueStore {
    final injected = widget.publishQueueStore;
    if (injected != null) return injected;
    return GetIt.instance.isRegistered<PublishQueueStore>()
        ? GetIt.instance<PublishQueueStore>()
        : null;
  }

  PublishQueueDrainer? get _queueDrainer {
    final injected = widget.publishQueueDrainer;
    if (injected != null) return injected;
    return GetIt.instance.isRegistered<PublishQueueDrainer>()
        ? GetIt.instance<PublishQueueDrainer>()
        : null;
  }

  /// Rebuilds the article a queued edit targets, so a resumed edit updates
  /// that article instead of creating a new one.
  ///
  /// The entry also supplies a cover URL when the author selected or uploaded
  /// one before queueing. The update re-reads the real article before writing.
  Blog? _queuedEditTarget() {
    final entry = widget.queueEntry;
    final targetId = entry?.targetId;
    if (entry == null ||
        entry.kind != PublishQueueKind.edit ||
        (targetId ?? '').isEmpty) {
      return null;
    }
    return Blog(
      id: targetId!,
      title: entry.title,
      content: entry.content,
      posterId: entry.userId,
      imageUrl: entry.coverUrl ?? '',
      tags: entry.tags,
      updatedAt: entry.updatedAt,
    );
  }

  /// Restores the cover a failed entry kept inside the app's storage. The text
  /// is already on screen: a missing cover only leaves the slot empty.
  Future<void> _loadQueuedCover(PublishQueueEntry entry) async {
    final selectionVersion = _coverSelectionVersion;
    final store = _queueStore;
    if (store == null) return;
    try {
      final cover = await store.readCover(entry);
      if (cover == null || !mounted || !_isCurrentEditor) return;
      // A slow read must not replace a cover the user picked meanwhile.
      if (_coverSelectionVersion != selectionVersion) return;
      setState(() {
        imageUpload = cover;
        imageBytes = cover.bytes;
        isNewImageSelected = true;
      });
    } catch (_) {
      // Reading local bytes failed; the text is still editable and publishable.
    }
  }

  /// Deletes the queue entry this editor resumed from, once the text has a
  /// successor: published, or queued again under a new idempotency key.
  ///
  /// Best effort by design. A leftover row is visible and removable, while
  /// deleting before the successor exists would lose the only copy.
  Future<void> _retireResumedEntry() async {
    final entry = widget.queueEntry;
    final store = _queueStore;
    if (entry == null || store == null) return;
    try {
      await store.remove(entry.id);
    } catch (_) {
      // The new intent is already safe; the stale row can be removed by hand.
    }
  }

  /// Failures a retry can plausibly fix. A rejected body, a permission denial
  /// or an expired session is not queued: sending it again would only fail
  /// again, and the user has to act first.
  static bool _isWorthQueueing(FailureKind kind) {
    if (kind == FailureKind.network || kind == FailureKind.timeout) {
      return true;
    }
    if (kind == FailureKind.server || kind == FailureKind.unknown) {
      return true;
    }
    return false;
  }

  /// Keeps a publish the network refused (issue #23).
  ///
  /// The queued entry carries the same idempotency key as the attempt that
  /// just failed, so the server either creates the article once or replays the
  /// one it already created - never a duplicate. An edit is queued against the
  /// article it updates instead: replaying an update rewrites that article, so
  /// it cannot create a second one either. Returns true when the entry is
  /// safely stored, which is what lets the page report "queued" instead of
  /// "failed".
  Future<bool> _queueFailedPublish() async {
    final snapshot = _publishedDraftSnapshot;
    final key = _publishIdempotencyKey;
    final store = _queueStore;
    final target = _target;
    if (snapshot == null || key == null || store == null) return false;
    try {
      await store.enqueue(
        userId: snapshot.userId,
        title: snapshot.title.trim(),
        content: snapshot.content.trim(),
        tags: List.of(snapshot.tags),
        idempotencyKey: key,
        cover: _publishImageSnapshot,
        coverUrl: _publishCoverUrlSnapshot,
        kind: target == null ? PublishQueueKind.create : PublishQueueKind.edit,
        targetId: target?.id,
        categoryIds: snapshot.categoryIds,
        // Persist the edition with the edit: a retry days later must not guess
        // the language from whatever the app displays then.
        locale: target?.locale,
      );
    } catch (_) {
      return false;
    }
    // The entry now holds the text, so the local draft is redundant; later
    // edits during the publish attempt are kept as a draft on purpose.
    await _retireResumedEntry();
    _publishIdempotencyKey = null;
    _publishStartedAt = null;
    _hasUnsavedEdits = _editedDuringPublish;
    await _clearPublishedDraft();
    _publishedDraftSnapshot = null;
    _publishImageSnapshot = null;
    _publishCoverUrlSnapshot = null;
    unawaited(_queueDrainer?.drain());
    return true;
  }

  Future<void> saveBlog() async {
    if (!_isCurrentEditor || _publishStartedAt != null) return;
    final version = ++_draftRequestVersion;
    // Cover and tags are optional (issue #17): title and body are the
    // only required fields, and the backend already publishes text-only
    // articles as plain content blocks.
    if (!formKey.currentState!.validate()) {
      showSnackBar(context, context.l10n.editorRequiredFields);
      return;
    }
    _autoSaveTimer?.cancel();
    _publishStartedAt = DateTime.now();
    _editedDuringPublish = false;
    final draft = _currentDraft();
    final publishImage = _target == null || isNewImageSelected
        ? imageUpload
        : null;
    final publishCoverUrl = isNewImageSelected ? _selectedCoverUrl : null;
    final sessionFence = NowaveSessionFence(
      userId: draft.userId,
      generation: _editorGeneration,
    );
    // A key identifies one intent to publish. It is generated once, before the
    // first request, and reused by every retry of that intent (#23).
    final idempotencyKey = _publishIdempotencyKey ??= const Uuid().v4();
    _publishImageSnapshot = publishImage;
    _publishCoverUrlSnapshot = publishCoverUrl;
    // Persist the exact request snapshot first. If the route is closed, the
    // account changes, or the server response is lost, the text survives.
    try {
      await _draftStore.save(draft);
    } catch (_) {
      if (mounted && _isCurrentEditor) {
        _publishStartedAt = null;
        if (_hasUnsavedEdits && _draftsReady) _scheduleAutoSave();
        showSnackBar(context, context.l10n.publishDraftSafetyFailed);
      }
      return;
    }
    if (!mounted || !_isCurrentEditor) return;
    _hasUnsavedEdits = version != _draftRequestVersion;
    _publishedDraftSnapshot = draft;
    if (_target == null) {
      context.read<BlogUploadBloc>().add(
        UploadBlogEvent(
          image: publishImage,
          uploadedCoverUrl: publishCoverUrl,
          title: draft.title.trim(),
          content: draft.content.trim(),
          posterId: draft.userId,
          tags: List.of(draft.tags),
          sessionFence: sessionFence,
          idempotencyKey: idempotencyKey,
          categoryIds: draft.categoryIds,
        ),
      );
    } else {
      context.read<BlogUploadBloc>().add(
        UpdateBlogEvent(
          blogId: _target.id,
          image: publishImage,
          uploadedCoverUrl: publishCoverUrl,
          title: draft.title.trim(),
          content: draft.content.trim(),
          tags: List.of(draft.tags),
          sessionFence: sessionFence,
          // Save the edition this editor was opened on, not the language the
          // interface happens to be showing now.
          locale: _target.locale,
          categoryIds: draft.categoryIds,
        ),
      );
    }
  }

  /// Reports a failed publish, keeping it in the queue when that is the only
  /// way the user does not lose the article (issue #23).
  Future<void> _reportPublishFailure(BlogUploadFailure failure) async {
    if (_isWorthQueueing(failure.failure.kind) && await _queueFailedPublish()) {
      if (!mounted || !_isCurrentEditor) return;
      showSnackBar(
        context,
        _target == null
            ? context.l10n.publishQueued
            : context.l10n.publishQueuedUpdate,
      );
      Navigator.of(context).pop(true);
      return;
    }
    _publishStartedAt = null;
    _publishedDraftSnapshot = null;
    if (_hasUnsavedEdits && _draftsReady) _scheduleAutoSave();
    if (!mounted || !_isCurrentEditor) return;
    showSnackBar(context, localizedFailure(context.l10n, failure.failure));
  }

  Future<void> saveDraft() async {
    if (!_isCurrentEditor) return;
    final version = ++_draftRequestVersion;
    // Take a snapshot before the first await: controllers may be edited or
    // disposed while the database transaction waits for its turn.
    final draft = _currentDraft();
    try {
      await _draftStore.save(draft);
      if (!mounted || !_isCurrentEditor) return;
      _hasUnsavedEdits = version != _draftRequestVersion;
      showSnackBar(context, context.l10n.draftSaved);
    } catch (_) {
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.draftSaveFailed);
      }
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _flushDraftOnDispose();
    final identitySubscription = _identitySubscription;
    final userSubscription = _userSubscription;
    if (identitySubscription != null) unawaited(identitySubscription.cancel());
    if (userSubscription != null) unawaited(userSubscription.cancel());
    _dismissRecoveryDialog();
    _dismissMediaPicker();
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCurrentEditor) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(NoWaveSpacing.large),
            child: Text(context.l10n.editorSessionChanged),
          ),
        ),
      );
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? AppPalette.ink : AppPalette.paper,
      appBar: EditorAppBar(
        isEditing: _target != null,
        onPublish: saveBlog,
        onSaveDraft: saveDraft,
        onCancel: () => Navigator.of(context).pop(),
      ),
      body: BlocConsumer<BlogUploadBloc, BlogUploadState>(
        listener: (context, state) {
          if (!_isCurrentEditor) return;
          if (state is BlogUploadFailure) {
            unawaited(_reportPublishFailure(state));
          } else if (state is BlogUploadSuccess) {
            // No manual imageCache eviction needed: covers use immutable
            // media URLs, whether picked from the library or newly uploaded.
            showSnackBar(
              context,
              _target == null
                  ? context.l10n.uploadSuccess
                  : context.l10n.updateSuccess,
            );
            // Clear only the exact published snapshot; later edits survive.
            _hasUnsavedEdits = _editedDuringPublish;
            unawaited(_retireResumedEntry());
            _publishIdempotencyKey = null;
            _publishImageSnapshot = null;
            _publishCoverUrlSnapshot = null;
            unawaited(_clearPublishedDraft());
            Navigator.of(context).pop(true);
          }
        },
        builder: (context, state) {
          if (state is BlogUploadLoading) {
            return const Center(child: NoWaveLoadingLabel());
          }
          return EditorForm(
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
            resumedFromQueue: widget.queueEntry != null,
            autoSaveStatus: _autoSaveStatus,
            onPickCover: selectImage,
            onChooseCoverFromLibrary: () => unawaited(selectCoverFromLibrary()),
            categories: _categories,
            selectedCategoryIds: _selectedCategoryIds,
            categoriesLoading: _categoriesLoading,
            categoriesFailed: _categoriesFailed,
            onCategoriesChanged: _onCategoriesChanged,
            onRetryCategories: () => unawaited(_loadCategories()),
          );
        },
      ),
    );
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
      final useCase = widget.getCategories ?? GetIt.instance<GetCategories>();
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
