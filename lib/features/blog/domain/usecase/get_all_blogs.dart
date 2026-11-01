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
    if (params.kind == BlogFeedKind.latest) {
      if (params.cursor == null) {
        return blogRepository.getAllBlogs(
          page: params.page,
          source: params.source,
        );
      }
      return blogRepository.getAllBlogs(
        page: params.page,
        source: params.source,
        cursor: params.cursor,
      );
    }
    return blogRepository.getOnlineFeed(
      page: params.page,
      kind: params.kind,
      expectedViewerId: params.expectedViewerId,
    );
  }
}

/// Page size agreed between the feed pagination and the remote data source.
/// A page returning fewer items than this means the end of the list.
const int kBlogPageSize = 10;

class GetAllBlogsParams {
  final int page;
  final BlogFeedSource? source;
  final BlogFeedKind kind;

  /// Local continuation from the prior latest network page, if available.
  final String? cursor;

  /// Local identity fence for the following feed, never an authorization
  /// parameter sent to the backend.
  final String? expectedViewerId;

  const GetAllBlogsParams({
    required this.page,
    this.source,
    this.kind = BlogFeedKind.latest,
    this.cursor,
    this.expectedViewerId,
  });
}
