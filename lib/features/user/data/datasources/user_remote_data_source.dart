import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class UserRemoteDataSource {
  Future<UserModel> getUserById(String userId);
  Future<String> uploadAvatar({required File image, required String userId});
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
  }) async {
    try {
      await supabaseClient.storage
          .from('avatars')
          .upload(userId, image, fileOptions: FileOptions(upsert: true));
      return supabaseClient.storage.from('avatars').getPublicUrl(userId);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<UserModel> editUserInfo(UserModel user) async {
    try {
      final userUpdated = await supabaseClient
          .from('profiles')
          .update(user.toJson())
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
      await supabaseClient.auth.updateUser(
        UserAttributes(email: newEmail),
      );
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
  }
}
