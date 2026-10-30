import 'package:belog/features/user/domain/entities/author_profile.dart';

/// Data-layer mapping for the no-wave author profile (issue #20).
///
/// The server serializes the profile row directly (camelCase keys,
/// counts as numbers, `isFollowing` resolved against the request's
/// viewer). Both `GET /authors/:userId` and the follow endpoints
/// return this shape inside the `data` envelope.
class AuthorProfileModel extends AuthorProfile {
  const AuthorProfileModel({
    required super.userId,
    super.displayName,
    super.bio,
    super.avatarUrl,
    super.websiteUrl,
    super.followerCount,
    super.followingCount,
    super.isFollowing,
    required super.updatedAt,
  });

  factory AuthorProfileModel.fromMap(Map<String, dynamic> map) {
    return AuthorProfileModel(
      userId: map['userId'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      bio: map['bio'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String? ?? '',
      websiteUrl: map['websiteUrl'] as String? ?? '',
      followerCount: _asInt(map['followerCount']),
      followingCount: _asInt(map['followingCount']),
      isFollowing: map['isFollowing'] == true,
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
