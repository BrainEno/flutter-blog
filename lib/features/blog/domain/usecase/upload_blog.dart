import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/common/entities/image_upload.dart';

class UploadBlog implements UseCase<Blog, UploadBlogParams> {
  final BlogRepository blogRepository;
  const UploadBlog(this.blogRepository);

  @override
  Future<Either<Failure, Blog>> call(UploadBlogParams params) async {
    return await blogRepository.uploadBlog(
      image: params.image,
      uploadedCoverUrl: params.uploadedCoverUrl,
      title: params.title,
      content: params.content,
      posterId: params.posterId,
      tags: params.tags,
      sessionFence: params.sessionFence,
      idempotencyKey: params.idempotencyKey,
      categoryIds: params.categoryIds,
    );
  }
}

class UploadBlogParams {
  /// Picked cover; null publishes a text-only article (issue #17).
  final ImageUpload? image;

  /// Existing immutable media URL chosen as the cover; avoids uploading it.
  final String? uploadedCoverUrl;
  final String title;
  final String content;
  final String posterId;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// Stable per publish intent (issue #23).
  ///
  /// A retry that reuses it lets the server replay the article it may have
  /// already created instead of publishing a duplicate; a brand-new publish
  /// must use a fresh key, or it would silently return the earlier article.
  final String? idempotencyKey;

  /// The author's category choice; null omits the field from the request, so
  /// the server keeps whatever the article already had.
  final List<String>? categoryIds;

  UploadBlogParams({
    required this.image,
    this.uploadedCoverUrl,
    required this.title,
    required this.content,
    required this.posterId,
    required this.tags,
    required this.sessionFence,
    this.idempotencyKey,
    this.categoryIds,
  });
}
