/// How many categories one article may carry.
///
/// The server takes at most 20 on `POST /articles` and, as of the audited
/// snapshot, 100 on `PUT /articles/:id` (`normalizeTaxonomyIds(…, 20)` vs
/// `(…, 100)`); more than that, a repeated id, or a non-UUID is a
/// `400 BAD_USER_INPUT`. The picker takes the tighter of the two: a queued
/// create has to satisfy it, and one number is easier to explain than two.
const int kMaxArticleCategories = 20;

/// A category as the server knows it.
///
/// The slug is server-generated and opaque: it is the only address
/// `GET /categories/:slug/articles` accepts, so the client carries it instead
/// of deriving one from [name]. Names are translated per content language, so
/// one category has a single slug and one name per language.
class CategoryRef {
  const CategoryRef({
    required this.slug,
    required this.name,
    this.description = '',
    this.id = '',
  });

  /// The server's UUID for this category, when the response carried one.
  ///
  /// Writing an article's category needs the id, not the slug (`categoryIds`),
  /// while every read addresses the slug. Empty means the value is unknown -
  /// an older response, or a hand-built ref - and a caller that must write
  /// treats it as "cannot pick this one".
  final String id;

  final String slug;

  /// The display name in the content language the request asked for.
  final String name;

  /// The editors' blurb in that same language; empty when there is none.
  final String description;

  @override
  bool operator ==(Object other) =>
      other is CategoryRef &&
      other.id == id &&
      other.slug == slug &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(id, slug, name, description);

  @override
  String toString() => 'CategoryRef($slug, $name)';
}
