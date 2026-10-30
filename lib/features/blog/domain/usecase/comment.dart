import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetComments implements UseCase<List<Comment>, String> {
  final CommentRepository commentRepository;
  const GetComments(this.commentRepository);

  @override
  Future<Either<Failure, List<Comment>>> call(String slug) {
    return commentRepository.getComments(slug);
  }
}

class CreateComment implements UseCase<Comment, CreateCommentParams> {
  final CommentRepository commentRepository;
  const CreateComment(this.commentRepository);

  @override
  Future<Either<Failure, Comment>> call(CreateCommentParams params) {
    return commentRepository.createComment(
      slug: params.slug,
      content: params.content,
      parentCommentId: params.parentCommentId,
      idempotencyKey: params.idempotencyKey,
    );
  }
}

class CreateCommentParams {
  final String slug;
  final String content;
  final String? parentCommentId;
  final String idempotencyKey;

  CreateCommentParams({
    required this.slug,
    required this.content,
    this.parentCommentId,
    required this.idempotencyKey,
  });
}

class DeleteComment implements UseCase<void, String> {
  final CommentRepository commentRepository;
  const DeleteComment(this.commentRepository);

  @override
  Future<Either<Failure, void>> call(String commentId) {
    return commentRepository.deleteComment(commentId);
  }
}
