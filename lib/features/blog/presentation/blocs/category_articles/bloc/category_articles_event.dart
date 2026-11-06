part of 'category_articles_bloc.dart';

@immutable
sealed class CategoryArticlesEvent {}

/// Opens (or re-opens) the list for the category with [slug].
final class CategoryArticlesRequested extends CategoryArticlesEvent {
  CategoryArticlesRequested({required this.slug});

  final String slug;
}

/// Pull-to-refresh: re-read the name and the first page for the same slug.
final class CategoryArticlesRefreshed extends CategoryArticlesEvent {}

/// Scrolls into the next page.
final class CategoryArticlesMoreRequested extends CategoryArticlesEvent {}
