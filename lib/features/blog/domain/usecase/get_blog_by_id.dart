import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetBlogById implements UseCase<Blog, GetBlogByIdParams> {
  final BlogRepository blogRepository;
  const GetBlogById(this.blogRepository);

  @override
  Future<Either<Failure, Blog>> call(GetBlogByIdParams params) {
    return blogRepository.getBlogById(params.blogId);
  }
}

class GetBlogByIdParams {
  final String blogId;

  GetBlogByIdParams({required this.blogId});
}
