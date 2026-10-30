import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Maximum results requested for one search; the backend may have more.
const int kMaxSearchResults = 50;

class SearchBlogs implements UseCase<List<Blog>, SearchBlogsParams> {
  final BlogRepository blogRepository;
  const SearchBlogs(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(SearchBlogsParams params) {
    return blogRepository.searchBlogs(params.query);
  }
}

class SearchBlogsParams {
  final String query;

  SearchBlogsParams({required this.query});
}
