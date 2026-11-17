import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetUserLikedBlogs
    implements UseCase<List<Blog>, GetUserLikedBlogsParams> {
  final BlogRepository blogRepository;
  const GetUserLikedBlogs(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(GetUserLikedBlogsParams params) {
    return blogRepository.getUserLikedBlogs(params.userId);
  }
}

class GetUserLikedBlogsParams {
  final String userId;

  GetUserLikedBlogsParams({required this.userId});
}
