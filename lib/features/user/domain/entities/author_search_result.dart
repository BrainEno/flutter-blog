/// The public fields of an author in the directory (ADR 0024). Discovery is
/// anonymous: viewer-specific follow state and account details are not
/// retained, so the same row is the same answer for every reader.
class AuthorSearchResult {
  const AuthorSearchResult({
    required this.userId,
    this.displayName = '',
    this.bio = '',
    this.followerCount = 0,
    this.workCount = 0,
  });

  final String userId;
  final String displayName;
  final String bio;

  /// Followers across the platform. This is the directory's reach ordering,
  /// shown so the order is explainable rather than mysterious.
  final int followerCount;

  /// Published works in the requested language. The directory lists nobody
  /// below one, so a zero here means the row went stale between requests.
  final int workCount;
}

/// One directory page holds at most 100 authors - the server's own limit for
/// `GET /api/v1/authors`. The directory has no cursor, so this is also the most
/// rows a single request can return.
const int maxAuthorSearchResults = 100;

/// The directory accepts up to 200 characters, but the client stops at 100: no
/// pen name is longer, and a longer query is a paste accident rather than a
/// search. Dart's `String.length` counts UTF-16 code units, the same unit the
/// service measures, so the two limits agree without re-encoding.
const int maxAuthorSearchQueryLength = 100;

/// A directory query may be empty - that is the browse case, ordered by reach.
/// A search must not be, and must not be padded into a different search
/// silently.
bool isValidAuthorSearchQuery(String query) =>
    query.isNotEmpty &&
    query == query.trim() &&
    query.length <= maxAuthorSearchQueryLength;
