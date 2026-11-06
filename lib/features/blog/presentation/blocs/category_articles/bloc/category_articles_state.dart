part of 'category_articles_bloc.dart';

@immutable
sealed class CategoryArticlesState {}

final class CategoryArticlesInitial extends CategoryArticlesState {}

final class CategoryArticlesLoading extends CategoryArticlesState {}

/// The server has no category with this slug (or it was removed since the link
/// was made). The page says so instead of listing everything, which is what a
/// silent empty list used to turn into.
final class CategoryArticlesNotFound extends CategoryArticlesState {
  CategoryArticlesNotFound({required this.slug});

  final String slug;
}

final class CategoryArticlesSuccess extends CategoryArticlesState {
  CategoryArticlesSuccess({
    required this.category,
    required this.articles,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailure,
  });

  /// The category as the server names it in this content language.
  final CategoryRef category;
  final List<Blog> articles;
  final bool hasMore;
  final bool loadingMore;

  /// A failed next page keeps the rows already on screen and offers a retry.
  final Failure? loadMoreFailure;

  bool get isEmpty => articles.isEmpty;

  CategoryArticlesSuccess copyWith({
    bool? loadingMore,
    Failure? loadMoreFailure,
  }) {
    return CategoryArticlesSuccess(
      category: category,
      articles: articles,
      hasMore: hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailure: loadMoreFailure,
    );
  }
}

final class CategoryArticlesFailure extends CategoryArticlesState {
  CategoryArticlesFailure({required this.failure});

  final Failure failure;

  /// Display-safe Chinese fallback; the UI localizes via `localizedFailure`.
  String get error => failure.message;
}
