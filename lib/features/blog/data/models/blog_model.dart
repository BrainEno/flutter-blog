import 'package:belog/features/blog/data/datasources/article_document_codec.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';

/// Data-layer representation of [Blog], including (de)serialization for the
/// remote backend. The SQLite adapter that persists it (and maps rows back to
/// this model) is `sqlite_blog_cache.dart`; `AppDatabase` itself only knows
/// primitive columns.
class BlogModel extends Blog {
  BlogModel({
    required super.id,
    required super.title,
    required super.content,
    required super.posterId,
    required super.imageUrl,
    required super.tags,
    required super.updatedAt,
    super.posterName,
    super.posterAvatar,
    super.isDraft,
    super.document,
    this.documentJson,
    this.articleId = '',
    this.publishedAt,
    this.serverSummary,
    this.plainEditorCompatible = false,
    super.locale,
    super.categoryIds,
    super.categories,
  });

  /// The no-wave server article id (UUID). [Blog.id] is the public slug;
  /// this is the address used by `PUT /articles/:articleId`.
  final String articleId;

  @override
  String? get authoringArticleId =>
      articleId.isNotEmpty && articleId == articleId.trim() ? articleId : null;

  /// Exact UTC millisecond timestamp returned by the server. It is only
  /// used for a live feed continuation and is not stored in the cache.
  final String? publishedAt;

  /// Original server body for the local read cache; never used for writes.
  /// Legacy Markdown models and pre-migration rows leave it null.
  final String? documentJson;

  /// The fresh server summary. Null means the value is unknown and an edit
  /// must fail closed instead of implicitly asking the server to regenerate it.
  final String? serverSummary;

  /// True only after inspecting a fresh server document known to use the
  /// plain editor's supported block shape. Cached/unknown models fail closed.
  final bool plainEditorCompatible;

  BlogModel copyWith({
    String? id,
    String? articleId,
    String? content,
    String? posterId,
    String? title,
    String? imageUrl,
    List<String>? tags,
    DateTime? updatedAt,
    String? posterName,
    String? posterAvatar,
    String? locale,
    List<String>? categoryIds,
    List<CategoryRef>? categories,
  }) {
    return BlogModel(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      publishedAt: publishedAt,
      document: content == null || content == this.content ? document : null,
      documentJson: content == null || content == this.content
          ? documentJson
          : null,
      serverSummary: serverSummary,
      plainEditorCompatible: plainEditorCompatible,
      content: content ?? this.content,
      posterId: posterId ?? this.posterId,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
      posterName: posterName ?? this.posterName,
      posterAvatar: posterAvatar ?? this.posterAvatar,
      isDraft: isDraft,
      locale: locale ?? this.locale,
      // Named categories win: they carry the names, and the ids come from them.
      // An id-only override loses the names it cannot know - that is what a
      // fixture building rows from bare ids asks for.
      categories: categories ?? (categoryIds == null ? this.categories : null),
      categoryIds: categories == null ? categoryIds : null,
    );
  }

  /// Builds a model from a serialized no-wave article
  /// (`serializeRestArticle`: the article row plus joined `author`,
  /// `categories` and `tags`).
  factory BlogModel.fromNowaveArticle(Map<String, dynamic> map) {
    final author = (map['author'] as Map<String, dynamic>?) ?? const {};
    final tags = (map['tags'] as List? ?? [])
        .map((tag) => (tag as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    // Categories travel as `{id, slug, name, description}`: the name is this
    // edition's rendering, so the reader can say where the article sits
    // without a second request. A malformed entry is dropped rather than
    // failing the article: it can still be read without that one chip.
    final categories = <CategoryRef>[];
    final seenCategories = <String>{};
    for (final value in map['categories'] as List? ?? const []) {
      if (value is! Map<String, dynamic>) continue;
      final id = value['id'];
      final slug = value['slug'];
      final name = value['name'];
      if (slug is! String ||
          slug.trim().isEmpty ||
          name is! String ||
          name.trim().isEmpty) {
        continue;
      }
      // One address per category: a repeated slug would be a second row with
      // the same destination.
      if (!seenCategories.add(slug)) continue;
      final description = value['description'];
      categories.add(
        CategoryRef(
          id: id is String ? id.trim() : '',
          slug: slug,
          name: name.trim(),
          description: description is String ? description.trim() : '',
        ),
      );
    }
    final rawBlocks = map['contentBlocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final version = map['contentBlocksVersion'];
    final document = decodeArticleDocument(version: version, blocks: rawBlocks);
    final extracted = extractBlogContent(blocks);
    return BlogModel(
      document: document,
      documentJson: document == null
          ? null
          : encodeArticleDocument(version: version, blocks: rawBlocks),
      plainEditorCompatible:
          document == null &&
          rawBlocks is List &&
          rawBlocks.length == blocks.length &&
          supportsPlainEditor(version: version, blocks: blocks),
      serverSummary: map['summary'] is String ? map['summary'] as String : null,
      // `status` is only present on the author's own rows; the public lists
      // serialize published work and never carry a draft.
      isDraft: map['status'] == 'draft',
      // The edition this row is, not the language it was requested in: the
      // server may answer a fallback edition under a different locale than the
      // query asked for, and writes must follow the body.
      locale: map['locale'] as String? ?? '',
      id: map['slug'] as String? ?? '',
      articleId: map['id'] as String? ?? '',
      publishedAt: map['publishedAt'] is String
          ? map['publishedAt'] as String
          : null,
      title: map['title'] as String? ?? '',
      content: extracted.content,
      posterId: map['authorId'] as String? ?? '',
      imageUrl: extracted.coverUrl,
      tags: tags,
      categories: categories,
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      posterName: author['displayName'] as String?,
      posterAvatar: author['avatarUrl'] as String?,
    );
  }
}
