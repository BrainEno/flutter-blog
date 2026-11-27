/// One row of the featured shelf, in the shape a curation screen needs.
///
/// [articleId] is the server's work UUID - the only thing `PUT /featured`
/// accepts - and [slug] is what the app addresses an article by everywhere
/// else. The domain `Blog` entity hides the UUID on purpose (an edit needs more
/// proof than an id), so the shelf carries its own pair instead of widening
/// that entity for every reader of a blog card.
class FeaturedShelfEntry {
  const FeaturedShelfEntry({
    required this.articleId,
    required this.slug,
    required this.title,
  });

  /// The work id sent back as an element of `articleIds`.
  final String articleId;

  /// The public slug, for opening the article the row names.
  final String slug;

  /// The title as the server wrote it in the locale the shelf was read in.
  final String title;
}
