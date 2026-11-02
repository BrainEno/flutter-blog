import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/domain/repositories/author_relationship_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetAuthorRelationships {
  const GetAuthorRelationships(this.repository);

  final AuthorRelationshipRepository repository;

  Future<Either<Failure, List<AuthorRelationship>>> call({
    required String userId,
    required AuthorRelationshipKind kind,
  }) => repository.getRelationships(userId: userId, kind: kind);
}
