/// Public author profile with the viewer's follow relationship (issue #20).
///
/// Pure Dart domain entity, mirroring [Blog] and [Comment]: free of
/// persistence and UI framework annotations. `isFollowing` is always
/// server-resolved — the follow state is never simulated locally.
class AuthorProfile {
  /// Stable user id; also the key the follow endpoints address.
  final String userId;
  final String displayName;
  final String bio;
  final String avatarUrl;
  final String websiteUrl;

  final int followerCount;
  final int followingCount;

  /// Whether the requesting viewer follows this author; false when the
  /// request was unauthenticated.
  final bool isFollowing;

  final DateTime updatedAt;

  const AuthorProfile({
    required this.userId,
    this.displayName = '',
    this.bio = '',
    this.avatarUrl = '',
    this.websiteUrl = '',
    this.followerCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    required this.updatedAt,
  });
}
