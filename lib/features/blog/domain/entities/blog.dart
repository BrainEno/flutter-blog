import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';

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

  /// Stable server work ID when the source can prove it. This is not the
  /// public slug and is never an authorization claim. Older/unknown sources
  /// leave it null; authoring must additionally validate owner and locale and
  /// fetch the exact edition under the current session fence.
  String? get authoringArticleId => null;

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

  /// The categories the server last said this article belongs to, with the
  /// names it rendered for this row's content language.
  ///
  /// Every article response joins the taxonomy (`serializeRestArticle` adds a
  /// `categories` array of `{id, slug, name, description}`), so a reader does
  /// not have to fetch the catalog to say where an article sits. Names are
  /// per language: this list describes *this edition*, not the article.
  ///
  /// Categories are editorial structure (ADR 0016): the desk may only choose
  /// among existing ones, never invent one. An empty list means "the server
  /// said it has none", not "unknown".
  final List<CategoryRef> categories;

  /// The same categories as ids - what an article write names (`categoryIds`).
  ///
  /// Derived, never stored beside [categories], so the editor and the reader
  /// cannot disagree about which categories an article has. A ref that was
  /// built from an id alone (a cache row written before names were kept) has
  /// an empty slug and name; the reader skips those because they cannot be
  /// opened, and the editor keeps showing them as the ids they are.
  List<String> get categoryIds => [
    for (final category in categories) category.id,
  ];

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
    List<String>? categoryIds,
    List<CategoryRef>? categories,
  }) : categories = List.unmodifiable(
         categories ??
             [
               for (final id in categoryIds ?? const <String>[])
                 CategoryRef(id: id, slug: '', name: ''),
             ],
       );
}
