import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';

/// Remote comments on a published article (issue #19).
///
/// The list endpoint returns the whole reply tree for each root comment,
/// oldest first. Continuations use the last root's exact `(createdAt, id)`;
/// creation takes the server's plain-text v0 contract plus an
/// `Idempotency-Key` header so a retried submit replays the original comment
/// instead of duplicating it.
abstract interface class CommentRemoteDataSource {
  Future<CommentPage> getComments(String slug, {String? cursor});

  Future<CommentModel> createComment({
    required String slug,
    required String content,
    String? parentCommentId,
    required String idempotencyKey,
  });

  Future<bool> deleteComment(String commentId);
}

class CommentRemoteDataSourceImpl implements CommentRemoteDataSource {
  /// The server accepts 1..100 top-level comments per page.
  static const int _kCommentLimit = 50;
  static const int _kMaxCursorLength = 512;
  static final RegExp _cursorTimestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );
  static final RegExp _cursorId = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final NowaveApiClient client;
  const CommentRemoteDataSourceImpl(this.client, {this.contentLocale});

  /// Content language for the requests this data source makes; null keeps the
  /// historical Chinese default for callers that never switch (tests).
  final ContentLocale? contentLocale;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  @override
  Future<CommentPage> getComments(String slug, {String? cursor}) async {
    final query = <String, String>{
      'locale': _locale,
      'limit': '$_kCommentLimit',
    };
    if (cursor != null) query['cursor'] = cursor;
    try {
      final data = await client.getJson(
        '/articles/$slug/comments',
        query: query,
      );
      return _commentPage(data);
    } catch (error) {
      // A valid cursor request rejected with 400 means this deployment does
      // not implement the continuation contract. Stop paging instead of
      // asking the user to retry an unsupported query forever.
      if (cursor != null &&
          error is NowaveApiException &&
          error.statusCode == 400) {
        throw const ServerException(
          'The server rejected comment pagination.',
          code: commentCursorUnavailableFailureCode,
        );
      }
      throw mapToServerException(error);
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
        query: {'locale': _locale},
        extraHeaders: {'Idempotency-Key': idempotencyKey},
      );
      if (data is! Map<String, dynamic>) {
        throw const ServerException('服务器返回了无法解析的数据', code: 'server.parse');
      }
      return CommentModel.fromMap(data);
    } catch (e) {
      if (e is NowaveApiException &&
          e.statusCode == 400 &&
          e.code == 'COMMENT_DEPTH_EXCEEDED') {
        throw ServerException(
          '回复层级已达上限，请回复此讨论中较早的评论',
          kind: FailureKind.validation,
          code: 'comments.depthExceeded',
          cause: e,
        );
      }
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> deleteComment(String commentId) async {
    try {
      final data = await client.deleteJson('/comments/$commentId');
      if (data is! Map<String, dynamic>) {
        throw const ServerException('服务器返回了无法解析的数据', code: 'server.parse');
      }
      return data['deleted'] == true;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  CommentPage _commentPage(dynamic data) {
    if (data is! List || data.length > _kCommentLimit) {
      throw const FormatException('Invalid comment page');
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in data) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid comment row');
      }
      rows.add(row);
    }
    final items = rows.map(CommentModel.fromMap).toList();
    if (rows.length < _kCommentLimit) {
      return CommentPage(items: items, nextCursor: null);
    }

    // The API compares the cursor against its stored `(created_at, id)` key.
    // Preserve the wire timestamp byte-for-byte; formatting a DateTime here
    // could change its timezone or precision. The array contains root comments
    // only, so its last row is the correct page boundary (not its last reply).
    final last = rows.last;
    final createdAt = last['createdAt'];
    final id = last['id'];
    if (createdAt is! String ||
        !_cursorTimestamp.hasMatch(createdAt) ||
        DateTime.tryParse(createdAt) == null ||
        id is! String ||
        !_cursorId.hasMatch(id)) {
      throw const FormatException('Invalid comment cursor row');
    }
    final nextCursor = base64Url
        .encode(utf8.encode('$createdAt|$id'))
        .replaceAll('=', '');
    if (nextCursor.isEmpty || nextCursor.length > _kMaxCursorLength) {
      throw const FormatException('Invalid comment cursor');
    }
    return CommentPage(items: items, nextCursor: nextCursor);
  }
}
