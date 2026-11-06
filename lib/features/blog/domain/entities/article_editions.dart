import 'package:belog/features/blog/domain/entities/blog.dart';

/// The author's own works read across language editions.
///
/// An article id is a *work*; `(id, locale)` is one of its translations. Two
/// editions of the same work share a slug, so this list can contain the same
/// [Blog.id] more than once - once per language it exists in. Callers that
/// key by id (a grid, a map) must key by `(id, locale)` instead.
class ArticleEditions {
  const ArticleEditions({required this.blogs, required this.locales});

  /// Newest update first across every locale the server read.
  final List<Blog> blogs;

  /// The locales the server said it read (`meta.locales`), in its order.
  ///
  /// Null means the deployment did not confirm the request: an older backend
  /// ignores `allLocales` and answers the single current language with a 200,
  /// which is indistinguishable from a complete list unless this marker is
  /// present. Null is therefore "unknown, probably only one language", never
  /// "every language is empty".
  final List<String>? locales;

  /// True when the server confirmed a multi-language read.
  bool get isConfirmed => locales != null;
}
