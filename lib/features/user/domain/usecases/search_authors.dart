import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:fpdart/fpdart.dart';

class SearchAuthors {
  const SearchAuthors(this.repository);

  final AuthorSearchRepository repository;

  Future<Either<Failure, List<AuthorSearchResult>>> call(
    String query, {
    int offset = 0,
  }) => repository.search(query, offset: offset);
}
