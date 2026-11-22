part of 'editor_session_coordinator.dart';

/// Publishing: the immutable intent, its offline-queue handoff, and the
/// version-conflict review. One idempotency key per intent (#23); a stale
/// conditional write is never queued.
mixin _EditorPublishFlow on _EditorSessionBase, _EditorDraftLifecycle {
  /// Deletes the queue entry this editor resumed from, once the text has a
  /// successor: published, or queued again under a new idempotency key.
  ///
  /// Best effort by design. A leftover row is visible and removable, while
  /// deleting before the successor exists would lose the only copy.
  Future<void> _retireResumedEntry() async {
    final entry = widget.config.queueEntry;
    final store = _queueStore;
    if (entry == null || store == null) return;
    try {
      await store.remove(entry.id);
    } catch (_) {
      // The new intent is already safe; the stale row can be removed by hand.
    }
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
    final intent = _publishIntent;
    final store = _queueStore;
    if (intent == null || store == null) return false;
    try {
      await intent.enqueue(store);
    } catch (_) {
      return false;
    }
    // The entry now holds the text, cover, locale and revision from the exact
    // dispatched request. Later edits during the request stay as a draft.
    await _retireResumedEntry();
    _publishIdempotencyKey = null;
    _publishStartedAt = null;
    _hasUnsavedEdits = _editedDuringPublish;
    await _clearPublishedDraft();
    _publishedDraftSnapshot = null;
    _publishIntent = null;
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
    if (_target != null && _expectedRevision == null) {
      // Older deployments and legacy drafts may not carry the server's exact
      // bigint revision. Persist the text best-effort, but never send the old
      // unguarded PUT merely because a revision is missing.
      try {
        await _draftStore.save(_currentDraft());
        _hasUnsavedEdits = false;
      } catch (_) {
        // The more important invariant remains that no remote request starts.
      }
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.errorArticleRevisionRequired);
      }
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
    // A key identifies one intent to publish. It is generated once, before the
    // first request, and reused by every retry of that intent (#23).
    final idempotencyKey = _publishIdempotencyKey ??= const Uuid().v4();
    final intent = EditorPublishIntent(
      draft: draft,
      target: _target,
      expectedRevision: _expectedRevision,
      image: publishImage,
      coverUrl: publishCoverUrl,
      sessionGeneration: _editorGeneration,
      idempotencyKey: idempotencyKey,
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
    _publishIntent = intent;
    context.read<BlogUploadBloc>().add(intent.buildEvent());
  }

  /// Reports a failed publish, keeping it in the queue when that is the only
  /// way the user does not lose the article (issue #23).
  /// A stale conditional write is never queued. A transport retry is safe only
  /// while it carries the original condition; once the server positively says
  /// it differs, automatically retrying can only hide the conflict from the
  /// author. The exact draft was stored before dispatch and stays on screen.
  Future<void> _reportVersionConflict(BlogUploadVersionConflict failure) async {
    _publishStartedAt = null;
    _publishedDraftSnapshot = null;
    _publishIntent = null;
    if (!mounted || !_isCurrentEditor) return;
    setState(() => _hasVersionConflict = true);
    showSnackBar(context, localizedFailure(context.l10n, failure.failure));
  }

  Future<void> _reportPublishFailure(BlogUploadFailure failure) async {
    if (EditorPublishIntent.shouldQueue(failure.failure) &&
        await _queueFailedPublish()) {
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
    _publishIntent = null;
    if (_hasUnsavedEdits && _draftsReady) _scheduleAutoSave();
    if (!mounted || !_isCurrentEditor) return;
    showSnackBar(context, localizedFailure(context.l10n, failure.failure));
  }

  /// Reads the newest article only after the author asks to review a conflict.
  /// Merely reading it never changes controllers or [_expectedRevision]. The
  /// author must inspect the three-way sheet and explicitly choose rebase; the
  /// rebased local draft is saved before the new condition is enabled.
  Future<void> _reviewVersionConflict() async {
    final target = _target;
    if (target == null ||
        !_isCurrentEditor ||
        !_hasVersionConflict ||
        _reviewingVersionConflict) {
      return;
    }
    setState(() => _reviewingVersionConflict = true);
    try {
      final getBlog =
          widget.config.getBlogById ?? GetIt.instance<GetBlogById>();
      final result = await getBlog(
        GetBlogByIdParams(blogId: target.id, requireFresh: true),
      );
      if (!mounted || !_isCurrentEditor) return;
      Blog? latest;
      Failure? failure;
      result.fold((error) => failure = error, (value) => latest = value);
      if (failure != null || latest == null || latest!.id != target.id) {
        showSnackBar(context, context.l10n.articleConflictUnavailable);
        return;
      }
      if (latest!.authoringRevision == null) {
        showSnackBar(context, context.l10n.articleConflictMissingRevision);
        return;
      }
      final choice = await showArticleConflictReviewSheet(
        context,
        openedArticle: target,
        localDraft: _currentDraft(),
        latestArticle: latest!,
      );
      if (!mounted ||
          !_isCurrentEditor ||
          choice != ArticleConflictReviewChoice.rebase) {
        return;
      }
      final revision = latest!.authoringRevision!;
      final rebasedDraft = _currentDraft(expectedRevision: revision);
      try {
        await _draftStore.save(rebasedDraft);
      } catch (_) {
        if (mounted && _isCurrentEditor) {
          showSnackBar(context, context.l10n.draftSaveFailed);
        }
        return;
      }
      if (!mounted || !_isCurrentEditor) return;
      setState(() {
        _expectedRevision = revision;
        _hasVersionConflict = false;
        _hasUnsavedEdits = false;
        _autoSaveStatus = AutoSaveStatus.saved;
      });
      showSnackBar(context, context.l10n.articleConflictRebased);
    } finally {
      if (mounted && _isCurrentEditor) {
        setState(() => _reviewingVersionConflict = false);
      }
    }
  }

  void _onUploadState(BuildContext context, BlogUploadState state) {
    if (!_isCurrentEditor) return;
    if (state is BlogUploadVersionConflict) {
      unawaited(_reportVersionConflict(state));
    } else if (state is BlogUploadFailure) {
      unawaited(_reportPublishFailure(state));
    } else if (state is BlogUploadSuccess) {
      // Covers use immutable media URLs; no manual imageCache eviction.
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
      _publishIntent = null;
      unawaited(_clearPublishedDraft());
      Navigator.of(context).pop(true);
    }
  }
}
