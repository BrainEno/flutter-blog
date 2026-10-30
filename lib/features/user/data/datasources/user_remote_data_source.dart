import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/models/user_model.dart';

/// User profile operations against the no-wave backend.
///
/// The profile is read via `GET /authors/:userId` and written via
/// `PUT /me/profile` (fields: displayName, bio, avatarUrl, websiteUrl).
/// E-mail/password changes have no backend endpoint yet (gap G2, see
/// docs/supabase-to-nowave-migration.md) and are therefore not offered;
/// avatar images are immutable media assets.
abstract interface class UserRemoteDataSource {
  Future<UserModel> getUserById(String userId);

  /// Uploads an avatar (`POST /me/media`, raw bytes + MIME type) and
  /// returns its immutable public URL. The server re-encodes to WebP.
  Future<String> uploadAvatar({required File image, String? mimeType});

  Future<UserModel> editUserInfo(UserModel user);
}

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  final NowaveApiClient client;
  final NowaveSessionManager sessionManager;

  UserRemoteDataSourceImpl(this.client, this.sessionManager);

  @override
  Future<UserModel> getUserById(String userId) async {
    try {
      final data = await client.getJson(
        '/authors/$userId',
        query: {'locale': 'zh-CN'},
      );
      return UserModel.fromNowaveProfile(
        _profileMap(data),
        email: sessionManager.currentSession?.email ?? '',
      );
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<String> uploadAvatar({required File image, String? mimeType}) async {
    try {
      final bytes = await image.readAsBytes();
      final asset = await client.uploadMedia(bytes, mimeType ?? 'image/jpeg');
      return client.mediaUri(asset.id).toString();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<UserModel> editUserInfo(UserModel user) async {
    try {
      // The write body is a strict whitelist: only fields with a value are
      // sent (empty strings are rejected for the URL fields server-side).
      final data = await client.putJson('/me/profile', <String, dynamic>{
        'displayName': user.name,
        'bio': '',
        if (user.avatarUrl.isNotEmpty) 'avatarUrl': user.avatarUrl,
        if (user.website.isNotEmpty) 'websiteUrl': user.website,
      });
      return UserModel.fromNowaveProfile(
        _profileMap(data),
        email: sessionManager.currentSession?.email ?? user.email,
      );
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  Map<String, dynamic> _profileMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw ServerException(
      '服务器返回了无法解析的数据',
      kind: FailureKind.server,
      cause: data,
    );
  }
}
