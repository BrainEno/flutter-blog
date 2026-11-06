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
  });

  final String slug;

  /// The display name in the content language the request asked for.
  final String name;

  /// The editors' blurb in that same language; empty when there is none.
  final String description;

  @override
  bool operator ==(Object other) =>
      other is CategoryRef &&
      other.slug == slug &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(slug, name, description);

  @override
  String toString() => 'CategoryRef($slug, $name)';
}
