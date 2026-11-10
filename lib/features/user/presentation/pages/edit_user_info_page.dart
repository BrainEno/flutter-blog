import 'dart:async';
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/user/presentation/widgets/user_media_picker_sheet.dart';
import 'package:get_it/get_it.dart';
import 'package:belog/core/utils/avatar_url.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';

class EditUserInfoPage extends StatefulWidget {
  const EditUserInfoPage({
    super.key,
    this.sessionIdentity,
    this.getUserMediaLibraryPage,
  });

  final NowaveSessionIdentity? sessionIdentity;
  final GetUserMediaLibraryPage? getUserMediaLibraryPage;

  @override
  State<EditUserInfoPage> createState() => _EditUserInfoPageState();
}

class _EditUserInfoPageState extends State<EditUserInfoPage> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _websiteController = TextEditingController();
  File? image;
  bool isNewImageSelected = false;

  /// The picked avatar's bytes and MIME type; [image] only feeds the preview.
  ImageUpload? avatarUpload;
  String? avatarUrl;
  String? email;
  DateTime? updatedAt;
  bool _isDisposed = false;
  bool _initialized = false;
  bool _invalidated = false;
  late final AppUserCubit _userCubit;
  late final NowaveSessionIdentity _session;
  NowaveSessionFence? _openingFence;
  StreamSubscription<void>? _identitySubscription;
  StreamSubscription<AppUserState>? _userSubscription;
  String? _selectedAvatarUrl;
  NavigatorState? _pickerNavigator;
  Route<dynamic>? _pickerRoute;
  bool _pickerOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _userCubit = context.read<AppUserCubit>();
    _session = widget.sessionIdentity ?? GetIt.instance<NowaveSessionManager>();
    final state = _userCubit.state;
    if (state is AppUserLoggedIn &&
        state.user.id.isNotEmpty &&
        state.user.id == _session.activeUserId &&
        !(_session.accessToken?.isEmpty ?? true)) {
      _openingFence = NowaveSessionFence(
        userId: state.user.id,
        generation: _session.sessionGeneration,
      );
      _nameController.text = state.user.name;
      _bioController.text = state.user.bio;
      _websiteController.text = state.user.website;
      avatarUrl = state.user.avatarUrl;
      email = state.user.email;
      updatedAt = state.user.updatedAt;
    } else {
      _invalidated = true;
    }
    _identitySubscription = _session.identityChanges.listen((_) {
      if (!_matchesSession) _invalidate();
    });
    _userSubscription = _userCubit.stream.listen((_) {
      if (!_matchesSession) _invalidate();
    });
  }

  bool get _matchesSession {
    final fence = _openingFence;
    final state = _userCubit.state;
    return !_invalidated &&
        fence != null &&
        state is AppUserLoggedIn &&
        state.user.id == fence.userId &&
        _session.activeUserId == fence.userId &&
        _session.sessionGeneration == fence.generation &&
        !(_session.accessToken?.isEmpty ?? true);
  }

  void _invalidate() {
    if (_invalidated) return;
    _invalidated = true;
    _dismissPicker();
    if (mounted) setState(() {});
  }

  void _dismissPicker() {
    if (!_pickerOpen) return;
    final navigator = _pickerNavigator;
    final route = _pickerRoute;
    _pickerOpen = false;
    _pickerNavigator = null;
    if (navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeRoute = route ?? _pickerRoute;
      if (navigator.mounted && activeRoute != null && activeRoute.isActive) {
        navigator.removeRoute(activeRoute);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _selectAvatarFromLibrary() async {
    if (!_matchesSession || _pickerOpen) return;
    final getPage =
        widget.getUserMediaLibraryPage ??
        (GetIt.instance.isRegistered<GetUserMediaLibraryPage>()
            ? GetIt.instance<GetUserMediaLibraryPage>()
            : null);
    if (getPage == null) {
      showSnackBar(context, context.l10n.userMediaPickerLoadFailed);
      return;
    }
    _pickerNavigator = Navigator.of(context, rootNavigator: true);
    _pickerOpen = true;
    UserMediaAsset? selected;
    try {
      selected = await showModalBottomSheet<UserMediaAsset>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (sheetContext) {
          _pickerRoute = ModalRoute.of(sheetContext);
          return UserMediaPickerSheet(
            getPage: getPage,
            sessionFence: _openingFence!,
            sessionIdentity: _session,
            purpose: UserMediaPickerPurpose.avatar,
          );
        },
      );
    } catch (_) {
      if (mounted && _matchesSession) {
        showSnackBar(context, context.l10n.userMediaPickerLoadFailed);
      }
    } finally {
      _pickerOpen = false;
      _pickerNavigator = null;
      _pickerRoute = null;
    }
    final asset = selected;
    if (asset == null || !mounted || !_matchesSession) return;
    setState(() {
      image = null;
      avatarUpload = null;
      _selectedAvatarUrl = asset.imageUrl;
      isNewImageSelected = true;
    });
  }

  void selectImage() async {
    if (!_matchesSession) return;
    try {
      final pickedImage = await pickImage();
      if (pickedImage != null && !_isDisposed && _matchesSession) {
        // check if disposed
        setState(() {
          image = pickedImage.file;
          avatarUpload = pickedImage.upload;
          _selectedAvatarUrl = null;
          isNewImageSelected = true;
        });
      }
      // null = the user cancelled the picker: nothing to do.
    } catch (_) {
      // Picking failed (as opposed to being cancelled): surface it
      // instead of silently keeping the old avatar.
      if (mounted && _matchesSession) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
    }
  }

  void _submit() {
    if (!_matchesSession) return;
    if (!_hasValidWebsite()) {
      showSnackBar(context, context.l10n.errorWebsiteUrl);
      return;
    }
    context.read<UserEditBloc>().add(
      UserEditSubmitted(
        name: _nameController.text,
        // Always forwarded: the backend treats a missing bio as an empty one,
        // so the pre-filled current value must survive an unrelated edit.
        bio: _bioController.text,
        website: _websiteController.text,
        avatar: isNewImageSelected ? avatarUpload : null,
        uploadedAvatarUrl: isNewImageSelected ? _selectedAvatarUrl : null,
        sessionFence: _openingFence,
      ),
    );
  }

  /// Mirrors the backend rule for `websiteUrl`: empty is fine (clearing the
  /// field), anything else must be an absolute http(s) URL - relative paths
  /// are only accepted for the avatar.
  bool _hasValidWebsite() {
    final raw = _websiteController.text.trim();
    if (raw.isEmpty) return true;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return uri.host.isNotEmpty;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _dismissPicker();
    unawaited(_identitySubscription?.cancel());
    unawaited(_userSubscription?.cancel());
    _nameController.dispose();
    _bioController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  /// Cache-busting parameter for the stored avatar: media assets are
  /// immutable, but a re-upload can keep the same path.
  String _versionedAvatar(String resolvedUrl) {
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) return resolvedUrl;
    final params = <String, String>{
      ...uri.queryParameters,
      'v': '${updatedAt?.millisecondsSinceEpoch ?? ''}',
    };
    return uri.replace(queryParameters: params).toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!_matchesSession) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.editProfileTitle)),
        body: Center(child: Text(context.l10n.editProfileSessionChanged)),
      );
    }
    // A site-relative avatar (`/avatars/me.webp`) needs the configured web
    // origin; without one the neutral portrait stays.
    final resolvedAvatarUrl = resolveAvatarUrl(avatarUrl);
    final ImageProvider<Object>? storedAvatarImage = resolvedAvatarUrl == null
        ? null
        : CachedNetworkImageProvider(_versionedAvatar(resolvedAvatarUrl));
    final selectedAvatar = _selectedAvatarUrl;
    final ImageProvider<Object>? pickedAvatarImage = selectedAvatar == null
        ? (image == null ? null : FileImage(image!))
        : CachedNetworkImageProvider(selectedAvatar);
    final shownAvatarImage = isNewImageSelected
        ? pickedAvatarImage
        : storedAvatarImage;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.editProfileTitle),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: context.l10n.actionSaveChanges,
            icon: const Icon(Icons.check),
            onPressed: _submit,
          ),
        ],
      ),
      body: BlocConsumer<UserEditBloc, UserEditState>(
        listener: (context, state) {
          if (state is UserEditSuccess) {
            Navigator.pop(context);
            showSnackBar(context, context.l10n.profileUpdated);
          } else if (state is UserEditFailure) {
            final l10n = context.l10n;
            final reason = localizedFailure(l10n, state.failure);
            showSnackBar(
              context,
              state.failure.code == 'auth.notSignedIn'
                  ? reason
                  : l10n.errorProfileSave(reason),
            );
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(NoWaveSpacing.large),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circle Avatar
                Tooltip(
                  message: context.l10n.changeAvatarTooltip,
                  child: InkWell(
                    onTap: selectImage,
                    customBorder: const CircleBorder(),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Semantics(
                          image: true,
                          label: context.l10n.avatarImage,
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            backgroundImage: shownAvatarImage,
                            child: shownAvatarImage != null
                                ? null
                                : Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(NoWaveSpacing.small),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.edit,
                            size: 20,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_selectAvatarFromLibrary()),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(context.l10n.editProfileChooseAvatarFromLibrary),
                ),
                const SizedBox(height: NoWaveSpacing.section),
                // Name Field
                TextFormField(
                  controller: _nameController,
                  autofocus: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.labelName,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: NoWaveSpacing.medium),
                // Public introduction: stored as the profile `bio`
                // (max 5000 chars) and shown on the author page.
                TextFormField(
                  controller: _bioController,
                  autofocus: false,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 5000,
                  decoration: InputDecoration(
                    labelText: context.l10n.labelBio,
                    prefixIcon: const Icon(Icons.notes_outlined),
                    alignLabelWithHint: true,
                  ),
                  keyboardType: TextInputType.multiline,
                ),
                const SizedBox(height: NoWaveSpacing.medium),
                // Homepage: a clearable field, so an empty value is valid.
                TextFormField(
                  controller: _websiteController,
                  autofocus: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.labelWebsite,
                    prefixIcon: const Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: NoWaveSpacing.medium),
                // Read-only e-mail row: the backend offers no e-mail
                // change endpoint yet (gap G2, see
                // docs/supabase-to-nowave-migration.md); the shown address
                // is the one cached at sign-in.
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.l10n.labelEmail,
                    prefixIcon: const Icon(Icons.email_outlined),
                    helperText: context.l10n.emailReadOnly,
                  ),
                  child: Text(
                    (email == null || email!.isEmpty)
                        ? context.l10n.notSet
                        : email!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: NoWaveSpacing.section),
                // The button stays where it is and shows its own busy state:
                // swapping it for an indicator made the form jump and lost the
                // only label that said what the wait was for.
                NoWaveButton(
                  label: context.l10n.actionSaveChanges,
                  onPressed: _submit,
                  isLoading: state is UserEditLoading,
                  expand: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
