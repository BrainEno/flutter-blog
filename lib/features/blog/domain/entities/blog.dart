import 'package:belog/features/blog/domain/entities/article_document.dart';

/// Published blog article.
///
/// Pure Dart domain entity: it must stay free of persistence and UI framework
/// annotations. Mapping to remote rows, the SQLite cache and the legacy Isar
/// collections lives in the data layer (`BlogModel` and
/// `lib/core/storage/legacy/`).
class Blog {
  /// Public identifier used for addressing: the article's slug on the
  /// no-wave backend (`GET /articles/:slug`, likes, deep links). The
  /// server's internal UUID is [BlogModel.articleId] in the data layer and
  /// is only needed for update requests.
  final String id;

  final String title;
  final String content;

  /// Structured server body for read-only rendering, or null for the
  /// app's legacy Markdown format. An unsupported document is explicit.
  final ArticleDocument? document;

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
    this.document,
    this.posterName,
    this.posterAvatar,
  });
}
