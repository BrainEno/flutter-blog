import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:fpdart/fpdart.dart';

/// Public, online-only relationship lists; never a snapshot of the viewer's
/// private follow state and never persisted in the offline cache.
abstract interface class AuthorRelationshipRepository {
  Future<Either<Failure, List<AuthorRelationship>>> getRelationships({
    required String userId,
    required AuthorRelationshipKind kind,
  });
}
