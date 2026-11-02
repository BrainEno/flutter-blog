import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:fpdart/fpdart.dart';

/// Public online search; neither the query nor result metadata is persisted.
abstract interface class AuthorSearchRepository {
  Future<Either<Failure, List<AuthorSearchResult>>> search(String query);
}
