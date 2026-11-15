import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetComments implements UseCase<CommentPage, String> {
  final CommentRepository commentRepository;
  const GetComments(this.commentRepository);

  @override
  Future<Either<Failure, CommentPage>> call(String slug, {String? cursor}) {
    return commentRepository.getComments(slug, cursor: cursor);
  }
}

class CreateComment implements UseCase<Comment, CreateCommentParams> {
  final CommentRepository commentRepository;
  const CreateComment(this.commentRepository, {this.sessionIdentity});
  final NowaveSessionIdentity? sessionIdentity;

  @override
  Future<Either<Failure, Comment>> call(CreateCommentParams params) {
    if (params.sessionFence == null) {
      return Future.value(left(Failure.auth('请先登录账户')));
    }
    return commentRepository.createComment(
      slug: params.slug,
      content: params.content,
      parentCommentId: params.parentCommentId,
      idempotencyKey: params.idempotencyKey,
      sessionFence: params.sessionFence!,
    );
  }
}

class CreateCommentParams {
  final String slug;
  final String content;
  final String? parentCommentId;
  final String idempotencyKey;
  final NowaveSessionFence? sessionFence;

  CreateCommentParams({
    required this.slug,
    required this.content,
    this.parentCommentId,
    required this.idempotencyKey,
    this.sessionFence,
  });
}

/// Write boundary for a comment correction. The server checks authorship; the
/// local fence prevents a dialog opened in one session from using another.
class EditComment {
  const EditComment(this.commentRepository);
  final CommentRepository commentRepository;

  Future<Either<Failure, Comment>> call({
    required String commentId,
    required String content,
    required NowaveSessionFence sessionFence,
  }) => commentRepository.editComment(
    commentId: commentId,
    content: content,
    sessionFence: sessionFence,
  );
}

class DeleteComment implements UseCase<void, String> {
  final CommentRepository commentRepository;
  const DeleteComment(this.commentRepository);

  @override
  Future<Either<Failure, void>> call(
    String commentId, {
    NowaveSessionFence? sessionFence,
  }) {
    if (sessionFence == null) return Future.value(left(Failure.auth('请先登录账户')));
    return commentRepository.deleteComment(
      commentId,
      sessionFence: sessionFence,
    );
  }
}
