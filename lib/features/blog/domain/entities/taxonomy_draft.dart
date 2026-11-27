/// What an editor typed, before the catalogue has accepted it (#381).
///
/// Not a `CategoryRef`: that one names a row the server already has, and its
/// `id` is what a later write addresses. A draft has
/// no id yet, and giving it a field for one would invite a screen to invent a
/// value - which is precisely how a public catalogue ends up with a row nobody
/// can delete.
class TaxonomyDraft {
  const TaxonomyDraft({
    required this.name,
    required this.slug,
    this.description = '',
  });

  /// The name readers see, in the language the catalogue is stored in.
  final String name;

  /// The address. `POST /taxonomies` requires it, unlike `POST /tags` where the
  /// server derives a slug from the hashtag, so the screen asks for one instead
  /// of deriving it from [name]: a transliteration invented here would be the
  /// permanent URL segment of an editorial category.
  final String slug;

  /// The editors' blurb. Optional server-side, and here empty means empty
  /// rather than "unchanged" - this write creates the row.
  final String description;
}
