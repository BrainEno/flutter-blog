part of 'blog_by_bloc.dart';

@immutable
sealed class BlogByEvent {}

/// Public, published articles of an arbitrary author (`/authors/:id/articles`).
final class GetBlogByPosterEvent extends BlogByEvent {
  final String userId;

  /// `latest` (the default) or `popular`. The two orders are separate lists:
  /// switching clears what the other one had read.
  final BlogFeedKind kind;

  GetBlogByPosterEvent({required this.userId, this.kind = BlogFeedKind.latest});
}

/// Scrolls into the next page of the author's list.
final class BlogByMoreRequested extends BlogByEvent {}

/// The viewer's own articles, drafts included (`/me/articles`). Kept separate
/// from [GetBlogByPosterEvent] because the source is account-scoped.
final class GetMyArticlesEvent extends BlogByEvent {
  final String userId;

  GetMyArticlesEvent({required this.userId});
}

/// The viewer's own articles across every language edition
/// (`GET /me/articles?allLocales=true`).
///
/// Separate from [GetMyArticlesEvent] because the answer can contain the same
/// work more than once - one row per translation - and carries the server's
/// confirmation of which locales it read.
final class GetMyArticleEditionsEvent extends BlogByEvent {
  final String userId;

  GetMyArticleEditionsEvent({required this.userId});
}
