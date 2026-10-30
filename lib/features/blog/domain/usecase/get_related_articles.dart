import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Related-articles rider on the viewer (issue #19): a handful of
/// same-topic articles the server recommends next to the one being read.
class GetRelatedArticles implements UseCase<List<Blog>, String> {
  final BlogRepository blogRepository;
  const GetRelatedArticles(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(String blogId) {
    return blogRepository.getRelatedArticles(blogId);
  }
}
