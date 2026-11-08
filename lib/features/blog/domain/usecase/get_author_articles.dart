import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// One page of an author's published work (`GET /authors/:id/articles`).
///
/// Kept apart from [GetBlogsByPoster], which reads a whole list at once for the
/// data export: a browse page has to know how far it has read, and an export
/// has to get everything a single request can carry.
class GetAuthorArticles
    implements UseCase<List<Blog>, GetAuthorArticlesParams> {
  final BlogRepository blogRepository;
  const GetAuthorArticles(this.blogRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(GetAuthorArticlesParams params) {
    return blogRepository.getAuthorArticlePage(
      params.userId,
      kind: params.kind,
      offset: params.offset,
    );
  }
}

class GetAuthorArticlesParams {
  final String userId;

  /// `latest` pages by publication date; `popular` by saves, and only as deep
  /// as the server allows.
  final BlogFeedKind kind;

  /// How many rows of this order are already on screen.
  final int offset;

  const GetAuthorArticlesParams({
    required this.userId,
    this.kind = BlogFeedKind.latest,
    this.offset = 0,
  });
}
