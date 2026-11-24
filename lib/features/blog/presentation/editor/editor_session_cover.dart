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

  Future<PickedImage?> Function() get _pickCover =>
      widget.config.pickCoverImage ?? pickImage;

  CoverCropper get _coverCropper =>
      widget.config.coverCropper ?? const CoverCropper();

  /// Picks a photo and opens the crop frame on it. Backing out of either step
  /// keeps whatever cover was there before.
  void selectImage() => unawaited(_pickAndCropCover());

  Future<void> _pickAndCropCover() async {
    if (!_isCurrentEditor) return;
    final PickedImage? picked;
    try {
      picked = await _pickCover();
    } catch (_) {
      // Picking failed (as opposed to being cancelled): surface it
      // instead of silently keeping the old cover.
      if (mounted && _isCurrentEditor) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
      return;
    }
    // null = the user cancelled the picker: nothing to do.
    if (picked == null || !mounted || !_isCurrentEditor) return;
    await _cropCover(picked.upload);
  }

  /// Reopens the frame on the uncut photo, where the last cut left it.
  Future<void> recropCover() async {
    final source = _coverCropSource;
    if (source == null || !mounted || !_isCurrentEditor) return;
    await _cropCover(source, initialRect: _coverCropRect);
  }

  /// Drops the cover chosen in this session. An article falls back to the
  /// cover it already has (the write sends none, and the server keeps its
  /// own); a new piece goes back to having none.
  void clearCoverSelection() {
    if (!_isCurrentEditor || !isNewImageSelected) return;
    _coverSelectionVersion++;
    setState(() {
      imageUpload = null;
      imageBytes = null;
      _selectedCoverUrl = null;
      _coverCropSource = null;
      _coverCropRect = null;
      isNewImageSelected = false;
    });
  }

  Future<void> _cropCover(ImageUpload source, {Rect? initialRect}) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = coverCropRoute(
      source: source.bytes,
      initialRect: initialRect,
      cropper: _coverCropper,
    );
    // The frame is a root route like the media sheet: an account change takes
    // it down through the same slot (see [_dismissMediaPicker]).
    _mediaPickerNavigator = navigator;
    _mediaPickerRoute = route;
    _mediaPickerOpen = true;
    CoverCropOutcome? outcome;
    try {
      outcome = await navigator.push(route);
    } finally {
      _mediaPickerOpen = false;
      _mediaPickerNavigator = null;
      _mediaPickerRoute = null;
    }
    final result = outcome;
    if (result == null || !mounted || !_isCurrentEditor) return;
    final cut = result.bytes;
    final rect = result.rect;
    _coverSelectionVersion++;
    setState(() {
      if (cut == null) {
        // The codec cannot read this photo: keep it uncut, as before there
        // was a crop step, rather than refusing the author's choice.
        imageBytes = source.bytes;
        imageUpload = source;
        _coverCropSource = null;
        _coverCropRect = null;
      } else {
        imageBytes = cut;
        imageUpload = ImageUpload(
          bytes: cut,
          mimeType: CoverCropLimits.mimeType,
        );
        _coverCropSource = source;
        _coverCropRect = rect;
      }
      _selectedCoverUrl = null;
      isNewImageSelected = true;
    });
    if (cut == null) {
      showSnackBar(context, context.l10n.coverCropUnsupported);
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
      imageUpload = null;
      imageBytes = null;
      _coverCropSource = null;
      _coverCropRect = null;
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
        // The stored cover was already cut once; reframing cuts it again.
        _coverCropSource = cover;
        _coverCropRect = null;
        isNewImageSelected = true;
      });
    } catch (_) {
      // Reading local bytes failed; the text is still editable and publishable.
    }
  }
}
