import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/user/data/datasources/author_relationship_remote_data_source.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/domain/repositories/author_relationship_repository.dart';
import 'package:fpdart/fpdart.dart';

class AuthorRelationshipRepositoryImpl implements AuthorRelationshipRepository {
  const AuthorRelationshipRepositoryImpl({
    required this.remote,
    required this.connectionChecker,
  });

  final AuthorRelationshipRemoteDataSource remote;
  final ConnectionChecker connectionChecker;

  @override
  Future<Either<Failure, List<AuthorRelationship>>> getRelationships({
    required String userId,
    required AuthorRelationshipKind kind,
  }) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(await remote.getRelationships(userId: userId, kind: kind));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }
}
