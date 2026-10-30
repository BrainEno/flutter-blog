import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:fpdart/fpdart.dart';

class CommentRepositoryImpl implements CommentRepository {
  final CommentRemoteDataSource commentRemoteDataSource;
  final ConnectionChecker connectionChecker;

  const CommentRepositoryImpl({
    required this.commentRemoteDataSource,
    required this.connectionChecker,
  });

  @override
  Future<Either<Failure, List<Comment>>> getComments(String slug) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }

      final res = await commentRemoteDataSource.getComments(slug);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('getComments failed', error: e, stackTrace: stackTrace);
      return left(Failure('评论加载失败，请稍后重试', code: 'comments.load'));
    }
  }

  @override
  Future<Either<Failure, Comment>> createComment({
    required String slug,
    required String content,
    String? parentCommentId,
    required String idempotencyKey,
  }) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(
          Failure(
            '无法连接到网络，评论未发送',
            kind: FailureKind.network,
            code: 'network.offline',
            l10nKey: 'comments.sendOffline',
          ),
        );
      }

      final res = await commentRemoteDataSource.createComment(
        slug: slug,
        content: content,
        parentCommentId: parentCommentId,
        idempotencyKey: idempotencyKey,
      );
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('createComment failed', error: e, stackTrace: stackTrace);
      return left(Failure('评论发送失败，请稍后重试', code: 'comments.send'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteComment(String commentId) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(
          Failure(
            '无法连接到网络，删除未同步',
            kind: FailureKind.network,
            code: 'network.offline',
            l10nKey: 'comments.deleteOffline',
          ),
        );
      }

      // `deleted: false` (already gone server-side) is treated as success:
      // the comment is gone either way, so the local tree just drops it.
      await commentRemoteDataSource.deleteComment(commentId);
      return right(null);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('deleteComment failed', error: e, stackTrace: stackTrace);
      return left(Failure('评论删除失败，请稍后重试', code: 'comments.delete'));
    }
  }
}
