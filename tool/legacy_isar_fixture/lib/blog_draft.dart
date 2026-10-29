import 'package:isar/isar.dart';

part 'blog_draft.g.dart';

/// Legacy Isar collection that mirrors the draft schema shipped in older app
/// versions.
///
/// It exists only so [AppDatabase.importLegacyIfNeeded] can read databases
/// written before the SQLite migration. The class name, property names,
/// property ids and the unique [blogId] index must stay exactly as the old
/// generator produced them, otherwise existing drafts become unreadable. The
/// live draft store is Drift/SQLite and the domain draft entity stays
/// persistence-free.
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
