/// The public fields shown when discovering an author. Search is anonymous:
/// viewer-specific follow state and account details are not retained.
class AuthorSearchResult {
  const AuthorSearchResult({
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

/// no-wave offers no offset, cursor or total for user search.
const int maxAuthorSearchResults = 100;

/// The service measures the input as JavaScript UTF-16 code units; Dart's
/// String.length has the same unit. A longer query must never be truncated
/// into a different search silently.
const int maxAuthorSearchQueryLength = 100;

bool isValidAuthorSearchQuery(String query) =>
    query.isNotEmpty &&
    query == query.trim() &&
    query.length <= maxAuthorSearchQueryLength;
