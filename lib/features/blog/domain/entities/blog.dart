import 'package:belog/features/blog/domain/entities/article_document.dart';

/// Published blog article.
///
/// Pure Dart domain entity: it must stay free of persistence and UI framework
/// annotations. Mapping to remote rows and the SQLite cache lives in the data
/// layer (`BlogModel` and `sqlite_blog_cache.dart`).
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

  /// The server edition this body came from (`zh-CN`, `zh-TW` or `en`), or
  /// an empty string when the source could not say.
  ///
  /// An article id is a *work*; `(id, locale)` is one of its translations, and
  /// the same slug can answer in more than one language. A write has to name
  /// the edition it means: the server treats an omitted `locale` on
  /// `PUT /articles/:articleId` as `zh-CN`, so echoing the *current* content
  /// language instead of this value would rewrite the wrong translation.
  /// Empty means unknown (an older cache row, a legacy local draft); callers
  /// that must not guess fall back to the content language and say so.
  final String locale;

  /// True only for the viewer's own server-side draft. Drafts never appear on
  /// public pages or in the shared cache; they are visible through the
  /// account-scoped "my articles" list, and saving one from the editor
  /// publishes it.
  final bool isDraft;

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
    this.isDraft = false,
    this.locale = '',
  });
}
