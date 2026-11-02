/// Which public relationship list to request for an author.
enum AuthorRelationshipKind { followers, following }

/// The no-wave endpoint has a limit but no cursor, offset, or total count.
const int maxAuthorRelationshipResults = 100;

/// Only the public fields displayed in a relationship list. Viewer-specific
/// `isFollowing` and account/session data are deliberately not retained.
class AuthorRelationship {
  const AuthorRelationship({
    required this.userId,
    this.displayName = '',
    this.bio = '',
    this.avatarUrl = '',
  });

  final String userId;
  final String displayName;
  final String bio;
  final String avatarUrl;
}
