import 'dart:async';
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/auto_save_banner.dart';
import 'package:belog/features/blog/presentation/editor/editor_app_bar.dart';
import 'package:belog/features/blog/presentation/editor/editor_form.dart';
import 'package:belog/features/blog/presentation/widgets/draft_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

/// Creates or edits an article.
///
/// The page is pushed as `/editor` (new article) or `/profile/editor` with
/// the article passed as `extra`. It pops with `true` when something was
/// published, updated or deleted, so the page below can refresh its list.
class BlogEditorPage extends StatefulWidget {
  final Blog? blog;
  final BlogDraftStore? draftStore;
  final NowaveSessionIdentity? sessionIdentity;
  const BlogEditorPage({
    super.key,
    this.blog,
    this.draftStore,
    this.sessionIdentity,
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
  File? image;
  bool isNewImageSelected = false;

  /// MIME type of [image] when a new cover was picked; uploaded as the
  /// object's contentType.
  String? imageMimeType;
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

  @override
  void initState() {
    super.initState();
    _draftStore = widget.draftStore ?? GetIt.instance<BlogDraftStore>();
    _userCubit = context.read<AppUserCubit>();
    _session = widget.sessionIdentity ?? GetIt.instance<NowaveSessionManager>();
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
    if (widget.blog != null && !_invalidated) {
      titleController.text = widget.blog!.title;
      contentController.text = widget.blog!.content;
      selectedTags = List.from(widget.blog!.tags);
    }
    // Attached after the initial text is in place, so pre-filling the
    // editors is not mistaken for an edit.
    titleController.addListener(_onEditorContentChanged);
    contentController.addListener(_onEditorContentChanged);
    if (!_invalidated) {
      loadDraft();
      _loadUnclaimedDraftNotice();
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
    blogId: widget.blog?.id,
    title: titleController.text,
    content: contentController.text,
    tags: List.of(selectedTags),
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
      final draft = await _draftStore.load(
        widget.blog?.id,
        userId: _draftOwnerId!,
      );
      if (!mounted ||
          !_isCurrentEditor ||
          requestVersion != _draftRequestVersion ||
          draft == null ||
          draft.userId != _draftOwnerId ||
          draft.blogId != widget.blog?.id) {
        return;
      }

      _recoveryNavigator = Navigator.of(context, rootNavigator: true);
      final choice = await showDraftRecoveryDialog(
        context,
        isOlderThanPublished:
            widget.blog != null &&
            widget.blog!.updatedAt.isAfter(draft.updatedAt),
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
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
    }
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
    final publishImage = widget.blog == null || isNewImageSelected
        ? image
        : null;
    final publishMimeType = publishImage == null ? null : imageMimeType;
    final sessionFence = NowaveSessionFence(
      userId: draft.userId,
      generation: _editorGeneration,
    );
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
    if (widget.blog == null) {
      context.read<BlogUploadBloc>().add(
        UploadBlogEvent(
          image: publishImage,
          title: draft.title.trim(),
          content: draft.content.trim(),
          posterId: draft.userId,
          tags: List.of(draft.tags),
          imageMimeType: publishMimeType,
          sessionFence: sessionFence,
        ),
      );
    } else {
      context.read<BlogUploadBloc>().add(
        UpdateBlogEvent(
          blogId: widget.blog!.id,
          image: publishImage,
          title: draft.title.trim(),
          content: draft.content.trim(),
          tags: List.of(draft.tags),
          imageMimeType: publishMimeType,
          sessionFence: sessionFence,
        ),
      );
    }
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
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.editorSessionChanged),
          ),
        ),
      );
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? AppPalette.ink : AppPalette.paper,
      appBar: EditorAppBar(
        isEditing: widget.blog != null,
        onPublish: saveBlog,
        onSaveDraft: saveDraft,
        onCancel: () => Navigator.of(context).pop(),
      ),
      body: BlocConsumer<BlogUploadBloc, BlogUploadState>(
        listener: (context, state) {
          if (!_isCurrentEditor) return;
          if (state is BlogUploadFailure) {
            _publishStartedAt = null;
            _publishedDraftSnapshot = null;
            if (_hasUnsavedEdits && _draftsReady) _scheduleAutoSave();
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
            // Clear only the exact published snapshot; later edits survive.
            _hasUnsavedEdits = _editedDuringPublish;
            unawaited(_clearPublishedDraft());
            Navigator.of(context).pop(true);
          }
        },
        builder: (context, state) {
          if (state is BlogUploadLoading) {
            return const Loader();
          }
          return EditorForm(
            formKey: formKey,
            titleController: titleController,
            contentController: contentController,
            selectedTags: selectedTags,
            onTagsChanged: _onTagsChanged,
            image: image,
            isNewImageSelected: isNewImageSelected,
            blog: widget.blog,
            hasUnclaimedDrafts: _hasUnclaimedDrafts,
            autoSaveStatus: _autoSaveStatus,
            onPickCover: selectImage,
          );
        },
      ),
    );
  }

  void _onTagsChanged(List<String> tags) {
    setState(() => selectedTags = tags);
    _onEditorContentChanged();
  }
}
