import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';

class EditUserInfoPage extends StatefulWidget {
  const EditUserInfoPage({super.key});

  @override
  State<EditUserInfoPage> createState() => _EditUserInfoPageState();
}

class _EditUserInfoPageState extends State<EditUserInfoPage> {
  final _nameController = TextEditingController();
  final _websiteController = TextEditingController();
  File? image;
  bool isNewImageSelected = false;

  /// MIME type of [image] when a new avatar was picked; uploaded as the
  /// object's contentType.
  String? avatarMimeType;
  String? avatarUrl;
  String? email;
  DateTime? updatedAt;
  bool _isDisposed = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    final state = context.read<AppUserCubit>().state;
    if (state is AppUserLoggedIn && !_initialized) {
      if (!_isDisposed) {
        _initialized = true;
        _nameController.text = state.user.name;
        _websiteController.text = state.user.website;
        avatarUrl = state.user.avatarUrl;
        email = state.user.email;
        updatedAt = state.user.updatedAt;
      }
    }
    super.didChangeDependencies();
  }

  void selectImage() async {
    try {
      final pickedImage = await pickImage();
      if (pickedImage != null && !_isDisposed) {
        // check if disposed
        setState(() {
          image = pickedImage.file;
          avatarMimeType = pickedImage.mimeType;
          isNewImageSelected = true;
        });
      }
      // null = the user cancelled the picker: nothing to do.
    } catch (_) {
      // Picking failed (as opposed to being cancelled): surface it
      // instead of silently keeping the old avatar.
      if (mounted) {
        showSnackBar(context, context.l10n.imagePickFailed);
      }
    }
  }

  void _submit() {
    context.read<UserEditBloc>().add(
      UserEditSubmitted(
        name: _nameController.text,
        website: _websiteController.text,
        avatar: isNewImageSelected ? image : null,
        avatarMimeType: isNewImageSelected ? avatarMimeType : null,
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true; // Set the flag
    _nameController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.all(24.0),
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
                            backgroundImage: isNewImageSelected
                                ? (image != null
                                      ? FileImage(image!)
                                            as ImageProvider<Object>?
                                      : null) // Added null check
                                : avatarUrl != null && avatarUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    '$avatarUrl?v=${updatedAt?.millisecondsSinceEpoch ?? ''}',
                                  )
                                : null,
                            child: isNewImageSelected || avatarUrl != null
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
                          padding: const EdgeInsets.all(8),
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
                const SizedBox(height: 32),
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _websiteController,
                  autofocus: false,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.labelBio,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 32),
                // Save Button or Loading Indicator
                if (state is UserEditLoading)
                  CircularProgressIndicator(
                    semanticsLabel: context.l10n.loading,
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        context.l10n.actionSaveChanges,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
