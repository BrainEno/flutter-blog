/// A deleted article in the author's recycle bin.
///
/// The no-wave backend keeps deletions as tombstones: the row survives,
/// leaves every list, and a sweep purges it for good once the retention
/// window (server policy, exposed per tombstone as [purgesAt]) runs out.
/// Until then the author can restore it - it comes back as a draft.
class DeletedBlog {
  /// The server's article UUID. This is the only address a tombstone
  /// still answers to (restore); the slug was released on deletion.
  final String articleId;

  final String title;

  /// Cover image URL, empty for text-only articles.
  final String imageUrl;

  /// When the article was deleted.
  final DateTime deletedAt;

  /// When the server sweep purges the tombstone for good, or null when
  /// the backend could not compute a promise.
  final DateTime? purgesAt;

  DeletedBlog({
    required this.articleId,
    required this.title,
    required this.imageUrl,
    required this.deletedAt,
    required this.purgesAt,
  });
}
