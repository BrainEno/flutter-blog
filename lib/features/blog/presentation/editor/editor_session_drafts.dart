part of 'editor_session_coordinator.dart';

/// Local drafts: debounced auto-save, recovery on open, the explicit save,
/// and the best-effort flush when the page goes away. Drafts are written
/// only on this device and only for the account that opened the editor.
mixin _EditorDraftLifecycle on _EditorSessionBase {
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
    _autoSaveTimer = Timer(AppDurations.editorAutoSave, _autoSaveDraft);
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

  BlogDraft _currentDraft({ArticleRevision? expectedRevision}) => BlogDraft(
    userId: _draftOwnerId!,
    blogId: _target?.id,
    title: titleController.text,
    content: contentController.text,
    tags: List.of(selectedTags),
    categoryIds: _categoryTouched ? List.of(_selectedCategoryIds) : null,
    expectedRevision: _target == null
        ? null
        : (expectedRevision ?? _expectedRevision),
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
            // The draft's own base wins even when a newly loaded list row has
            // a revision. Adopting the latter would authorize stale text.
            if (_target != null) _expectedRevision = draft.expectedRevision;
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
}
