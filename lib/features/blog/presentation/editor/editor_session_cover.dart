part of 'editor_session_coordinator.dart';

/// The cover: picked from the device, chosen from the media library, or
/// restored from a queued entry. A later choice always wins over a slow read.
mixin _EditorCoverSelection on _EditorSessionBase {
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
        widget.config.getUserMediaLibraryPage ??
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
}
