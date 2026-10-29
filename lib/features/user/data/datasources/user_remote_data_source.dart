import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/storage_objects.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class UserRemoteDataSource {
  Future<UserModel> getUserById(String userId);

  /// Uploads an avatar to a fresh, versioned object path and returns its
  /// public URL. [mimeType] is sent as the object's contentType.
  Future<String> uploadAvatar({
    required File image,
    required String userId,
    String? mimeType,
  });

  /// Removes the avatar object a public URL points at. Throws on failure;
  /// callers decide whether that is fatal or an orphan to log.
  Future<void> removeAvatar(String publicUrl);

  Future<UserModel> editUserInfo(UserModel user);
  Future<void> changeEmail(String newEmail);
  Future<void> changePassword(String newPassword);
}

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  final SupabaseClient supabaseClient;
  UserRemoteDataSourceImpl(this.supabaseClient);

  @override
  Future<String> uploadAvatar({
    required File image,
    required String userId,
    String? mimeType,
  }) async {
    try {
      final path = avatarObjectPath(
        userId: userId,
        version: storageVersionNow(),
        extension: extensionForMime(mimeType),
      );
      await supabaseClient.storage.from(kAvatarsBucket).upload(
            path,
            image,
            fileOptions: FileOptions(
              // Explicit MIME so the object is served with the right
              // Content-Type (the picker already re-encoded the bytes).
              contentType: mimeType ?? 'image/jpeg',
              // Fresh versioned path: never overwrite in place, so the
              // old avatar stays reachable until the profile row flips.
              upsert: false,
            ),
          );
      return supabaseClient.storage.from(kAvatarsBucket).getPublicUrl(path);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<void> removeAvatar(String publicUrl) async {
    // Parses both legacy flat paths (path = user id) and current
    // versioned paths, and ignores cache-busting query parameters.
    final path = objectPathFromPublicUrl(publicUrl);
    if (path == null) {
      AppLogger.debug('avatar cleanup skipped: unrecognized object URL');
      return;
    }
    try {
      await supabaseClient.storage.from(kAvatarsBucket).remove([path]);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<UserModel> editUserInfo(UserModel user) async {
    try {
      // toProfileUpdateJson() deliberately excludes the e-mail column:
      // the auth e-mail only changes via Supabase Auth's confirmation
      // flow (changeEmail), never a direct profiles write.
      final userUpdated = await supabaseClient
          .from('profiles')
          .update(user.toProfileUpdateJson())
          .eq('id', user.id)
          .select()
          .single();
      return UserModel.fromJson(userUpdated);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<UserModel> getUserById(String userId) async {
    try {
      final res = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(res);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<void> changeEmail(String newEmail) async {
    try {
      // Supabase sends a confirmation email; the outcome surfaces through
      // the returned future or a thrown error - there is nothing to print.
      await supabaseClient.auth.updateUser(UserAttributes(email: newEmail));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<void> changePassword(String newPassword) async {
    try {
      await supabaseClient.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      // Never swallow: the repository must see the failure so the UI
      // reports it instead of pretending the password was changed.
      throw mapToServerException(e);
    }
    // The password changed: revoke sessions on other devices but keep the
    // current one signed in. Best-effort - the password itself already
    // changed, so a failure here must not fail the whole operation.
    try {
      await supabaseClient.auth.signOut(scope: SignOutScope.others);
    } catch (e) {
      AppLogger.error(
        'revoking other sessions after password change failed',
        error: e,
      );
    }
  }
}
