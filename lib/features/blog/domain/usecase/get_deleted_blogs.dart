import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetDeletedBlogs implements UseCase<List<DeletedBlog>, NoParams> {
  final BlogRepository blogRepository;

  const GetDeletedBlogs(this.blogRepository);

  @override
  Future<Either<Failure, List<DeletedBlog>>> call(NoParams params) async {
    return await blogRepository.getDeletedBlogs();
  }
}
