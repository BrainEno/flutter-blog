import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The viewer's own works across every language edition, scoped to [userId].
class GetMyArticleEditions
    implements UseCase<ArticleEditions, GetMyArticleEditionsParams> {
  final BlogRepository blogRepository;
  const GetMyArticleEditions(this.blogRepository);

  @override
  Future<Either<Failure, ArticleEditions>> call(
    GetMyArticleEditionsParams params,
  ) {
    return blogRepository.getMyArticleEditions(userId: params.userId);
  }
}

class GetMyArticleEditionsParams {
  final String userId;

  GetMyArticleEditionsParams({required this.userId});
}
