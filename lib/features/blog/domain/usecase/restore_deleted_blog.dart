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
    return await blogRepository.restoreDeletedBlog(
      params.articleId,
      locale: params.locale,
    );
  }
}

class RestoreDeletedBlogParams {
  /// The server article UUID of the tombstone (a tombstone no longer
  /// answers to its slug).
  final String articleId;

  /// The edition the tombstone is in; null means the current content
  /// language. Restoring the wrong translation reports "not found" for a row
  /// the user can see in the bin.
  final String? locale;

  RestoreDeletedBlogParams({required this.articleId, this.locale});
}
