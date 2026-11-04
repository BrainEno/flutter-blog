import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/core/common/entities/image_upload.dart';

/// User profile operations against the no-wave backend.
///
/// The profile is read via `GET /authors/:userId` and written via
/// `PUT /me/profile` (fields: displayName, bio, avatarUrl, websiteUrl).
/// Direct e-mail/password changes are not offered (gap G2, see
/// docs/supabase-to-nowave-migration.md); the backend's separate password
/// recovery and e-mail verification flows are not integrated here either.
/// Avatar images are immutable media assets.
abstract interface class UserRemoteDataSource {
  Future<UserModel> getUserById(String userId);

  /// Uploads an avatar (`POST /me/media`, raw bytes + MIME type) and
  /// returns its immutable public URL. The server re-encodes to WebP.
  Future<String> uploadAvatar({
    required ImageUpload image,
    NowaveSessionFence? sessionFence,
  });

  Future<UserModel> editUserInfo(
    UserModel user, {
    NowaveSessionFence? sessionFence,
  });
}

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  final NowaveApiClient client;
  final NowaveSessionManager sessionManager;

  UserRemoteDataSourceImpl(
    this.client,
    this.sessionManager, {
    this.contentLocale,
  });

  /// Content language for the requests this data source makes; null keeps the
  /// historical Chinese default for callers that never switch (tests).
  final ContentLocale? contentLocale;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;


  @override
  Future<UserModel> getUserById(String userId) async {
    try {
      final data = await client.getJson(
        '/authors/$userId',
        query: {'locale': _locale},
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
  Future<String> uploadAvatar({
    required ImageUpload image,
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      final asset = await client.uploadMedia(
        image.bytes,
        image.mimeType,
        sessionFence: sessionFence,
      );
      return client.mediaUri(asset.id).toString();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<UserModel> editUserInfo(
    UserModel user, {
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      // The write body is a strict whitelist (no-wave
      // `normalizeProfileWriteBody`): `displayName` is required, `bio`
      // defaults to '' when absent, and the URL fields keep their stored value
      // when absent but reject '' - clearing them requires null.
      final website = user.website.trim();
      final data = await client.putJson('/me/profile', <String, dynamic>{
        'displayName': user.name,
        // Always sent: omitting it would silently wipe the public bio.
        'bio': user.bio,
        if (user.avatarUrl.isNotEmpty) 'avatarUrl': user.avatarUrl,
        'websiteUrl': website.isEmpty ? null : website,
      }, sessionFence: sessionFence);
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
      code: 'server.parse',
      kind: FailureKind.server,
      cause: data,
    );
  }
}
