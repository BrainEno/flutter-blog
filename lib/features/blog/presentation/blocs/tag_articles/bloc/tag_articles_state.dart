part of 'tag_articles_bloc.dart';

@immutable
sealed class TagArticlesState {}

final class TagArticlesInitial extends TagArticlesState {}

final class TagArticlesLoading extends TagArticlesState {}

/// The server has no tag by this name (or it vanished mid-session). The page
/// says so instead of listing everything, which is what a silent empty list
/// used to turn into.
final class TagArticlesUnknown extends TagArticlesState {
  final String tag;

  TagArticlesUnknown({required this.tag});
}

final class TagArticlesSuccess extends TagArticlesState {
  final TagRef tag;
  final List<Blog> articles;
  final bool hasMore;
  final bool loadingMore;

  /// A failed next page keeps the rows already on screen and offers a retry.
  final Failure? loadMoreFailure;

  TagArticlesSuccess({
    required this.tag,
    required this.articles,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailure,
  });

  bool get isEmpty => articles.isEmpty;

  TagArticlesSuccess copyWith({
    bool? loadingMore,
    Failure? loadMoreFailure,
  }) {
    return TagArticlesSuccess(
      tag: tag,
      articles: articles,
      hasMore: hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailure: loadMoreFailure,
    );
  }
}

final class TagArticlesFailure extends TagArticlesState {
  final Failure failure;

  TagArticlesFailure({required this.failure});

  /// Display-safe Chinese fallback; the UI localizes via `localizedFailure`
  /// (issue #24).
  String get error => failure.message;
}
