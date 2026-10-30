import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';

/// Remote comments on a published article (issue #19).
///
/// The list endpoint returns the whole thread tree, oldest first, with
/// replies nested under their direct parent; creation takes the server's
/// plain-text v0 contract plus an `Idempotency-Key` header so a retried
/// submit replays the original comment instead of duplicating it.
abstract interface class CommentRemoteDataSource {
  Future<List<CommentModel>> getComments(String slug);

  Future<CommentModel> createComment({
    required String slug,
    required String content,
    String? parentCommentId,
    required String idempotencyKey,
  });

  Future<bool> deleteComment(String commentId);
}

class CommentRemoteDataSourceImpl implements CommentRemoteDataSource {
  static const _kCommentLimit = 50;

  final NowaveApiClient client;
  const CommentRemoteDataSourceImpl(this.client);

  @override
  Future<List<CommentModel>> getComments(String slug) async {
    try {
      final data = await client.getJson(
        '/articles/$slug/comments',
        query: {'locale': 'zh-CN', 'limit': '$_kCommentLimit'},
      );
      return _commentList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<CommentModel> createComment({
    required String slug,
    required String content,
    String? parentCommentId,
    required String idempotencyKey,
  }) async {
    try {
      final data = await client.postJson(
        '/articles/$slug/comments',
        {'content': content, 'parentCommentId': parentCommentId},
        query: {'locale': 'zh-CN'},
        extraHeaders: {'Idempotency-Key': idempotencyKey},
      );
      if (data is! Map<String, dynamic>) {
        throw const ServerException('服务器返回了无法解析的数据');
      }
      return CommentModel.fromMap(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> deleteComment(String commentId) async {
    try {
      final data = await client.deleteJson('/comments/$commentId');
      if (data is! Map<String, dynamic>) {
        throw const ServerException('服务器返回了无法解析的数据');
      }
      return data['deleted'] == true;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  List<CommentModel> _commentList(dynamic data) {
    if (data is! List) {
      throw const ServerException('服务器返回了无法解析的数据');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(CommentModel.fromMap)
        .toList();
  }
}
