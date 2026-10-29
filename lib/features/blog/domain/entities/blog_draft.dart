/// Local draft of a blog article.
///
/// Pure Dart domain entity: it must stay free of persistence annotations. A
/// draft is scoped to [blogId] (`null` means a brand-new article), and [id] is
/// the local row id assigned by [BlogDraftStore] when the draft is persisted;
/// it is `null` until then and must never leak into UI logic.
class BlogDraft {
  int? id;

  final String? blogId;
  final String title;
  final String content;
  final List<String> tags;
  final DateTime updatedAt;

  BlogDraft({
    this.id,
    this.blogId,
    required this.title,
    required this.content,
    required this.tags,
    required this.updatedAt,
  });
}
