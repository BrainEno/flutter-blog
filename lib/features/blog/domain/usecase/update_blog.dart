import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/usecase/usecase.dart';
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
      image: params.image,
      title: params.title,
      content: params.content,
      tags: params.tags,
      locale: params.locale,
      sessionFence: params.sessionFence,
    );
  }
}

class UpdateBlogParams {
  final String blogId;
  final ImageUpload? image;
  final String title;
  final String content;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// The edition this save belongs to (the article's own `locale`). Null means
  /// the current content language; naming the wrong one rewrites the wrong
  /// translation, because the server replaces exactly that edition.
  final String? locale;

  UpdateBlogParams({
    required this.blogId,
    this.image,
    required this.title,
    required this.content,
    required this.tags,
    required this.sessionFence,
    this.locale,
  });
}
