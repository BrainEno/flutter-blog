import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetBlogsByPoster implements UseCase<List<Blog>, GetBlogsByPosterParams> {
  final BlogRepository blogRepository;
  const GetBlogsByPoster(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(GetBlogsByPosterParams params) {
    return blogRepository.getBlogsByUser(params.userId);
  }
}

class GetBlogsByPosterParams {
  final String userId;

  GetBlogsByPosterParams({required this.userId});
}
