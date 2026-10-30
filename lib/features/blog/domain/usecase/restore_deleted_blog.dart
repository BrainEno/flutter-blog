import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class RestoreDeletedBlog implements UseCase<Blog, RestoreDeletedBlogParams> {
  final BlogRepository blogRepository;

  const RestoreDeletedBlog(this.blogRepository);

  @override
  Future<Either<Failure, Blog>> call(RestoreDeletedBlogParams params) async {
    return await blogRepository.restoreDeletedBlog(params.articleId);
  }
}

class RestoreDeletedBlogParams {
  /// The server article UUID of the tombstone (a tombstone no longer
  /// answers to its slug).
  final String articleId;

  RestoreDeletedBlogParams({required this.articleId});
}
