import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
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
  Future<UserMediaPage> getMediaLibraryPage({
    required NowaveSessionFence sessionFence,
    String? cursor,
  });

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

const _mediaLibraryPageSize = 24;
final _mediaIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
);
final _mediaTimeZonePattern = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$');

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
  Future<UserMediaPage> getMediaLibraryPage({
    required NowaveSessionFence sessionFence,
    String? cursor,
  }) async {
    try {
      if (cursor != null && cursor.isEmpty) {
        throw const FormatException('Invalid media library cursor');
      }
      _requireMediaSession(sessionFence);
      final data = await client.getJsonForViewer(
        '/me/media',
        expectedUserId: sessionFence.userId,
        query: {
          'limit': '$_mediaLibraryPageSize',
          if (cursor != null) 'cursor': cursor,
        },
      );
      _requireMediaSession(sessionFence);
      return _mediaLibraryPage(data);
    } on NowaveApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        throw ServerException(
          'The configured server does not support the media library endpoint.',
          kind: FailureKind.server,
          code: 'user.mediaLibraryUnavailable',
          cause: error,
        );
      }
      throw mapToServerException(error);
    } catch (error) {
      throw mapToServerException(error);
    }
  }

  void _requireMediaSession(NowaveSessionFence sessionFence) {
    if (sessionManager.activeUserId != sessionFence.userId ||
        sessionManager.sessionGeneration != sessionFence.generation ||
        (sessionManager.accessToken?.isEmpty ?? true)) {
      throw const NowaveApiException(
        statusCode: 409,
        code: 'SESSION_CHANGED',
        message: 'The media picker session no longer matches its viewer.',
      );
    }
  }

  UserMediaPage _mediaLibraryPage(dynamic data) {
    if (data is! Map<String, dynamic> ||
        data['items'] is! List ||
        !data.containsKey('nextCursor')) {
      throw const FormatException('Invalid media library page');
    }
    final rawCursor = data['nextCursor'];
    if (rawCursor != null && (rawCursor is! String || rawCursor.isEmpty)) {
      throw const FormatException('Invalid media library cursor');
    }
    final rows = data['items'] as List;
    if (rows.length > _mediaLibraryPageSize ||
        (rows.isEmpty && rawCursor != null)) {
      throw const FormatException('Invalid media library page size');
    }

    final ids = <String>{};
    final items = <UserMediaAsset>[];
    for (final value in rows) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid media library item');
      }
      final id = value['id'];
      final source = value['src'];
      final contentType = value['contentType'];
      final byteSize = value['byteSize'];
      final width = value['width'];
      final height = value['height'];
      final rawCreatedAt = value['createdAt'];
      if (id is! String ||
          !_mediaIdPattern.hasMatch(id) ||
          !ids.add(id) ||
          source is! String ||
          source.isEmpty ||
          contentType != 'image/webp' ||
          byteSize is! int ||
          byteSize < 1 ||
          width is! int ||
          width < 1 ||
          height is! int ||
          height < 1 ||
          rawCreatedAt is! String ||
          !_mediaTimeZonePattern.hasMatch(rawCreatedAt)) {
        throw const FormatException('Invalid media library item');
      }
      final createdAt = DateTime.tryParse(rawCreatedAt);
      if (createdAt == null) {
        throw const FormatException('Invalid media creation time');
      }
      items.add(
        UserMediaAsset(
          id: id,
          imageUrl: client.mediaUri(id).toString(),
          width: width,
          height: height,
          byteSize: byteSize,
          createdAt: createdAt,
        ),
      );
    }
    return UserMediaPage(items: items, nextCursor: rawCursor as String?);
  }

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
