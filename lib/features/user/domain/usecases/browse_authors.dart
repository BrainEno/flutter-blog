import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The empty-query half of the author directory: who publishes here at all,
/// ordered by reach rather than by name match.
class BrowseAuthors {
  const BrowseAuthors(this.repository);

  final AuthorSearchRepository repository;

  Future<Either<Failure, List<AuthorSearchResult>>> call({int offset = 0}) =>
      repository.directory(offset: offset);
}
