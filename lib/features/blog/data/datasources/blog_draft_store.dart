import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:isar/isar.dart';

/// Local drafts are scoped to an article ID, or null for a new article.
abstract class BlogDraftStore {
  Future<BlogDraft?> load(String? blogId);
  Future<void> save(BlogDraft draft);
  Future<bool> discardIfUnchanged(BlogDraft draft);
}

class IsarBlogDraftStore implements BlogDraftStore {
  final Isar isar;

  IsarBlogDraftStore(this.isar);

  Future<BlogDraft?> _load(String? blogId) => isar.blogDrafts
      .filter()
      .blogIdEqualTo(blogId)
      .sortByUpdatedAtDesc()
      .findFirst();

  @override
  Future<BlogDraft?> load(String? blogId) => _load(blogId);

  @override
  Future<void> save(BlogDraft draft) async {
    await isar.writeTxn(() async {
      final existing = await _load(draft.blogId);
      // Reuse the latest row instead of deleting it before writing. In
      // particular, do not assume that a nullable unique index has only one
      // legacy null-ID row, or delete older rows that may contain user work.
      if (existing != null) draft.id = existing.id;
      await isar.blogDrafts.put(draft);
    });
  }

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async {
    return isar.writeTxn(() async {
      final current = await isar.blogDrafts.get(draft.id);
      if (current == null ||
          current.blogId != draft.blogId ||
          current.updatedAt != draft.updatedAt) {
        return false;
      }
      return isar.blogDrafts.delete(draft.id);
    });
  }
}
