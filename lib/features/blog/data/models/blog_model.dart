import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';

/// Data-layer representation of [Blog], including (de)serialization for the
/// remote backend. Persistence concerns (SQLite cache, legacy Isar import)
/// live in `lib/core/storage/` and map to/from this model.
class BlogModel extends Blog {
  BlogModel({
    required super.id,
    required super.title,
    required super.content,
    required super.posterId,
    required super.imageUrl,
    required super.tags,
    required super.updatedAt,
    super.posterName,
    super.posterAvatar,
    this.articleId = '',
  });

  /// The no-wave server article id (UUID). [Blog.id] is the public slug;
  /// this is the address used by `PUT /articles/:articleId`.
  final String articleId;

  BlogModel copyWith({
    String? id,
    String? articleId,
    String? content,
    String? posterId,
    String? title,
    String? imageUrl,
    List<String>? tags,
    DateTime? updatedAt,
    String? posterName,
    String? posterAvatar,
  }) {
    return BlogModel(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      content: content ?? this.content,
      posterId: posterId ?? this.posterId,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
      posterName: posterName ?? this.posterName,
      posterAvatar: posterAvatar ?? this.posterAvatar,
    );
  }

  /// Builds a model from a serialized no-wave article
  /// (`serializeRestArticle`: the article row plus joined `author`,
  /// `categories` and `tags`).
  factory BlogModel.fromNowaveArticle(Map<String, dynamic> map) {
    final author = (map['author'] as Map<String, dynamic>?) ?? const {};
    final tags = (map['tags'] as List? ?? [])
        .map((tag) => (tag as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    final extracted = extractBlogContent(
      (map['contentBlocks'] as List? ?? []).cast<Map<String, dynamic>>(),
    );
    return BlogModel(
      id: map['slug'] as String? ?? '',
      articleId: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: extracted.content,
      posterId: map['authorId'] as String? ?? '',
      imageUrl: extracted.coverUrl,
      tags: tags,
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      posterName: author['displayName'] as String?,
      posterAvatar: author['avatarUrl'] as String?,
    );
  }
}
