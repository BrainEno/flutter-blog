/// Local draft of a blog article.
///
/// Pure Dart domain entity: it must stay free of persistence annotations. A
/// draft is scoped to [userId] and [blogId] (`null` means a brand-new
/// article). The backend namespace is applied by the storage implementation.
/// [id] is assigned when the draft is persisted; it is not a server id.
class BlogDraft {
  int? id;

  final String userId;
  final String? blogId;
  final String title;
  final String content;
  final List<String> tags;
  final DateTime updatedAt;

  BlogDraft({
    this.id,
    required this.userId,
    this.blogId,
    required this.title,
    required this.content,
    required List<String> tags,
    required this.updatedAt,
  }) : tags = List.unmodifiable(tags);
}
