import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// One page of a tag's published articles. [offset] walks the server's
/// newest-first ordering; a short page is the end of the list.
class GetArticlesByTag implements UseCase<List<Blog>, TagArticlesParams> {
  final BlogRepository blogRepository;
  const GetArticlesByTag(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(TagArticlesParams params) {
    return blogRepository.getArticlesByTag(params.slug, offset: params.offset);
  }
}

class TagArticlesParams {
  final String slug;
  final int offset;

  TagArticlesParams({required this.slug, required this.offset});
}
