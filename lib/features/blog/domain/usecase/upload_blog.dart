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
      title: params.title,
      content: params.content,
      posterId: params.posterId,
      tags: params.tags,
      sessionFence: params.sessionFence,
    );
  }
}

class UploadBlogParams {
  /// Picked cover; null publishes a text-only article (issue #17).
  final ImageUpload? image;
  final String title;
  final String content;
  final String posterId;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  UploadBlogParams({
    required this.image,
    required this.title,
    required this.content,
    required this.posterId,
    required this.tags,
    required this.sessionFence,
  });
}
