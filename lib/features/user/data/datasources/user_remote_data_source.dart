import 'dart:io';

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
      throw ServerException(e.toString());
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
      throw ServerException(e.toString());
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
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> changeEmail(String newEmail) async {
    try {
      final response = await supabaseClient.auth.updateUser(
        UserAttributes(email: newEmail),
      );

      if (response.user != null) {
        print('Email update initiated successfully. Check your inbox.');
        // You might want to show a success message to the user.
      }
    } catch (e) {
      throw ServerException('Unexpected error updating email: ${e.toString()}');
    }
  }

  @override
  Future<void> changePassword(String newPassword) async {
    try {
      final response = await supabaseClient.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (response.user != null) {
        // Password updated successfully.
        print('Password updated successfully.');
        // You might want to show a success message and potentially navigate the user.
      }
    } catch (e) {
      print('Unexpected error updating password: $e');
      // Handle unexpected errors.
    }
  }
}
