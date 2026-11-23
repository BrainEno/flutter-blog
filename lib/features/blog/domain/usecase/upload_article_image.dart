import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Uploads a picture placed inside an article's body and answers its
/// immutable media URL, which the editor then writes into the text.
///
/// The same media endpoint stores covers; only where the URL goes differs.
class UploadArticleImage implements UseCase<String, UploadArticleImageParams> {
  final BlogRepository blogRepository;
  const UploadArticleImage(this.blogRepository);

  @override
  Future<Either<Failure, String>> call(UploadArticleImageParams params) {
    return blogRepository.uploadCover(
      image: params.image,
      sessionFence: params.sessionFence,
    );
  }
}

class UploadArticleImageParams {
  final ImageUpload image;

  /// The editor's account and session: an upload started before a switch
  /// must not land in the next account's library.
  final NowaveSessionFence? sessionFence;

  const UploadArticleImageParams({required this.image, this.sessionFence});
}
