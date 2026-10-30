import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:fpdart/fpdart.dart';

/// Public author profile and the viewer's follow relationship (issue #20).
abstract interface class AuthorRepository {
  /// The author's public profile; `isFollowing` is resolved against the
  /// current viewer (false when signed out). A missing author is a
  /// [Failure] the page renders as "not found".
  Future<Either<Failure, AuthorProfile>> getAuthorProfile(String userId);

  /// Follows the author and returns the fresh profile the server sends
  /// back — the follow state stays server-resolved, never simulated.
  /// Duplicate follows are idempotent server-side.
  Future<Either<Failure, AuthorProfile>> followAuthor(String userId);

  /// Unfollows the author and returns the fresh profile. Duplicate
  /// unfollows are idempotent server-side.
  Future<Either<Failure, AuthorProfile>> unfollowAuthor(String userId);
}
