import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:fpdart/fpdart.dart';

/// Public author discovery; neither the query nor result metadata is persisted.
///
/// `search` narrows the directory by name; `directory` browses it ordered by
/// reach (ADR 0024). Both are anonymous and only list authors with a published
/// work in the requested language.
abstract interface class AuthorSearchRepository {
  Future<Either<Failure, List<AuthorSearchResult>>> search(String query);
  Future<Either<Failure, List<AuthorSearchResult>>> directory();
}
