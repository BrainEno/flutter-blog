import 'package:isar/isar.dart';

part 'blog_draft.g.dart';

@Collection()
class BlogDraft {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  final String? blogId; // null for new blog drafts

  final String title;
  final String content;
  final List<String> tags;
  final DateTime updatedAt;

  BlogDraft({
    this.blogId,
    required this.title,
    required this.content,
    required this.tags,
    required this.updatedAt,
  });
}
