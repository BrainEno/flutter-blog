import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/user/data/datasources/author_search_remote_data_source.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:fpdart/fpdart.dart';

class AuthorSearchRepositoryImpl implements AuthorSearchRepository {
  const AuthorSearchRepositoryImpl({
    required this.remote,
    required this.connectionChecker,
  });

  final AuthorSearchRemoteDataSource remote;
  final ConnectionChecker connectionChecker;

  @override
  Future<Either<Failure, List<AuthorSearchResult>>> search(String query) async {
    final trimmed = query.trim();
    if (!isValidAuthorSearchQuery(trimmed)) {
      return left(Failure.validation('搜索关键词不符合要求'));
    }
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(await remote.search(trimmed));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, List<AuthorSearchResult>>> directory() async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(await remote.directory());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }
}
