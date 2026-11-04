part of 'tag_articles_bloc.dart';

@immutable
sealed class TagArticlesEvent {}

/// Opens (or re-opens) the list for [tag], the name stored on the article.
final class TagArticlesRequested extends TagArticlesEvent {
  final String tag;

  TagArticlesRequested({required this.tag});
}

/// Pull-to-refresh: re-read the first page for the same tag.
final class TagArticlesRefreshed extends TagArticlesEvent {}

/// Scrolls into the next page.
final class TagArticlesMoreRequested extends TagArticlesEvent {}
