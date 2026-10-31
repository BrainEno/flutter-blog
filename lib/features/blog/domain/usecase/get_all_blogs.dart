import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetAllBlogs implements UseCase<BlogFeedPage, GetAllBlogsParams> {
  final BlogRepository blogRepository;
  const GetAllBlogs(this.blogRepository);

  @override
  Future<Either<Failure, BlogFeedPage>> call(GetAllBlogsParams params) {
    return blogRepository.getAllBlogs(page: params.page, source: params.source);
  }
}

/// Page size agreed between the feed pagination and the remote data source.
/// A page returning fewer items than this means the end of the list.
const int kBlogPageSize = 10;

class GetAllBlogsParams {
  final int page;
  final BlogFeedSource? source;

  const GetAllBlogsParams({required this.page, this.source});
}
