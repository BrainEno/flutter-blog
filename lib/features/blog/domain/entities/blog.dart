/// Published blog article.
///
/// Pure Dart domain entity: it must stay free of persistence and UI framework
/// annotations. Mapping to remote rows, the SQLite cache and the legacy Isar
/// collections lives in the data layer (`BlogModel` and
/// `lib/core/storage/legacy/`).
class Blog {
  /// Stable business identifier (the remote row id).
  final String id;

  final String title;
  final String content;
  final String posterId;
  final String imageUrl;
  final List<String> tags;
  final DateTime updatedAt;

  /// Author display fields, resolved from the joined profile when available.
  final String? posterName;
  final String? posterAvatar;

  Blog({
    required this.id,
    required this.title,
    required this.content,
    required this.posterId,
    required this.imageUrl,
    required this.tags,
    required this.updatedAt,
    this.posterName,
    this.posterAvatar,
  });
}
