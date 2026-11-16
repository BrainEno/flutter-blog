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
    return params.requireFresh
        ? blogRepository.getBlogById(params.blogId, requireFresh: true)
        : blogRepository.getBlogById(params.blogId);
  }
}

class GetBlogByIdParams {
  final String blogId;

  /// Conflict review must compare against a response obtained now. In
  /// particular, it may not use an offline cache response with the revision
  /// that just failed its conditional write.
  final bool requireFresh;

  GetBlogByIdParams({required this.blogId, this.requireFresh = false});
}
