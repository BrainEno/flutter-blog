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

  /// The category the author picked, or null when the picker was never
  /// touched.
  ///
  /// Null and an empty list are different promises: null means "leave the
  /// article's categories alone" (the write omits `categoryIds` entirely,
  /// because categories are editorial structure the app cannot recreate),
  /// while an empty list means the author explicitly removed it.
  final List<String>? categoryIds;

  final DateTime updatedAt;

  BlogDraft({
    this.id,
    required this.userId,
    this.blogId,
    required this.title,
    required this.content,
    required List<String> tags,
    required this.updatedAt,
    List<String>? categoryIds,
  }) : tags = List.unmodifiable(tags),
       categoryIds = categoryIds == null
           ? null
           : List.unmodifiable(categoryIds);
}
