import 'package:belog/features/blog/domain/entities/comment.dart';

/// Data-layer mapping for the no-wave comment contract (issue #19).
///
/// The server returns the plain-text `content` fallback alongside the
/// versioned blocks; the client renders comments as plain text, so only the
/// fallback is mapped. `author` is the joined profile and may be null.
class CommentModel extends Comment {
  const CommentModel({
    required super.id,
    required super.articleId,
    required super.authorId,
    super.parentCommentId,
    required super.content,
    super.authorName = '',
    super.authorAvatarUrl = '',
    required super.createdAt,
    super.replies = const [],
  });

  factory CommentModel.fromMap(Map<String, dynamic> map) {
    final author = map['author'] as Map<String, dynamic>?;
    return CommentModel(
      id: map['id'] as String? ?? '',
      articleId: map['articleId'] as String? ?? '',
      authorId: map['authorId'] as String? ?? '',
      parentCommentId: map['parentCommentId'] as String?,
      content: map['content'] as String? ?? '',
      authorName: author?['displayName'] as String? ?? '',
      authorAvatarUrl: author?['avatarUrl'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      replies: (map['replies'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommentModel.fromMap)
          .toList(),
    );
  }
}
