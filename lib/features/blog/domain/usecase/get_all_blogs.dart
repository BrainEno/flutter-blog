import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetAllBlogs implements UseCase<List<Blog>, GetAllBlogsParams> {
  final BlogRepository blogRepository;
  const GetAllBlogs(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(GetAllBlogsParams params) async {
    return await blogRepository.getAllBlogs(page: params.page);
  }
}

/// Page size agreed between the feed pagination and the remote data source.
/// A page returning fewer items than this means the end of the list.
const int kBlogPageSize = 10;

class GetAllBlogsParams {
  final int page;

  GetAllBlogsParams({required this.page});
}
