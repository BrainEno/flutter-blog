import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The viewer's own articles, drafts included, scoped to [userId].
class GetMyArticles implements UseCase<List<Blog>, GetMyArticlesParams> {
  final BlogRepository blogRepository;
  const GetMyArticles(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(GetMyArticlesParams params) {
    return blogRepository.getMyArticles(userId: params.userId);
  }
}

class GetMyArticlesParams {
  final String userId;

  GetMyArticlesParams({required this.userId});
}
