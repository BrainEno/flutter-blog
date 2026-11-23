import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/common/entities/image_upload.dart';

class UpdateBlog implements UseCase<Blog, UpdateBlogParams> {
  final BlogRepository blogRepository;
  const UpdateBlog(this.blogRepository);

  @override
  Future<Either<Failure, Blog>> call(UpdateBlogParams params) async {
    return await blogRepository.editBlog(
      blogId: params.blogId,
      expectedRevision: params.expectedRevision,
      image: params.image,
      uploadedCoverUrl: params.uploadedCoverUrl,
      title: params.title,
      content: params.content,
      tags: params.tags,
      locale: params.locale,
      sessionFence: params.sessionFence,
      categoryIds: params.categoryIds,
      summary: params.summary,
      publish: params.publish,
    );
  }
}

class UpdateBlogParams {
  final String blogId;

  /// Opaque server revision captured when the author opened/rebased this
  /// editor. It cannot be reconstructed safely during this update.
  final ArticleRevision expectedRevision;
  final ImageUpload? image;

  /// Existing immutable media URL chosen as the cover; avoids uploading it.
  final String? uploadedCoverUrl;
  final String title;
  final String content;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// The edition this save belongs to (the article's own `locale`). Null means
  /// the current content language; naming the wrong one rewrites the wrong
  /// translation, because the server replaces exactly that edition.
  final String? locale;

  /// The author's category choice; null leaves the article's categories as
  /// they are, an empty list clears them.
  final List<String>? categoryIds;

  /// The author's summary; null keeps the server's summary, empty asks it for a new one.
  final String? summary;

  /// False stores a private draft instead of publishing.
  final bool publish;

  UpdateBlogParams({
    required this.blogId,
    required this.expectedRevision,
    this.image,
    this.uploadedCoverUrl,
    required this.title,
    required this.content,
    required this.tags,
    required this.sessionFence,
    this.locale,
    this.categoryIds,
    this.summary,
    this.publish = true,
  });
}
