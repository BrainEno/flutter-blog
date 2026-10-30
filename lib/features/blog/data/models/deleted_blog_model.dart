import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';

/// Data-layer representation of a recycle-bin tombstone
/// (`GET /me/articles/deleted`: the serialized article row plus
/// `deletedAt` and the server-computed `purgesAt`).
class DeletedBlogModel extends DeletedBlog {
  DeletedBlogModel({
    required super.articleId,
    required super.title,
    required super.imageUrl,
    required super.deletedAt,
    required super.purgesAt,
  });

  /// Builds a tombstone from a serialized no-wave deleted article. The
  /// deleted row keeps the full article shape (title, content blocks,
  /// ...), so the cover is extracted with the shared article codec.
  factory DeletedBlogModel.fromNowaveArticle(Map<String, dynamic> map) {
    final extracted = extractBlogContent(
      (map['contentBlocks'] as List? ?? []).cast<Map<String, dynamic>>(),
    );
    return DeletedBlogModel(
      articleId: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      imageUrl: extracted.coverUrl,
      deletedAt:
          DateTime.tryParse(map['deletedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      // Absent when the backend could not read the tombstone timestamp -
      // the entry is still listed, it just carries no expiry promise.
      purgesAt: DateTime.tryParse(map['purgesAt'] as String? ?? ''),
    );
  }
}
