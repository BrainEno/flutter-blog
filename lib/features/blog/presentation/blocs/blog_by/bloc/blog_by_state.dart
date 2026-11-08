part of 'blog_by_bloc.dart';

@immutable
sealed class BlogByState {}

final class BlogByInitial extends BlogByState {}

final class GetBlogsByUserSuccess extends BlogByState {
  final List<Blog> blogs;

  /// The order this list is in. A page fetched in the other order never merges
  /// into it: the offsets would mean two different things.
  final BlogFeedKind kind;

  /// Whether the last page came back full, which is the only "maybe more" the
  /// route offers.
  final bool hasMore;

  final bool loadingMore;

  /// A failed next page keeps the rows already on screen and offers a retry.
  final Failure? loadMoreFailure;

  /// The most-saved order ended at the server's bound, not at the end of the
  /// author's work.
  final bool depthLimited;

  GetBlogsByUserSuccess({
    required this.blogs,
    this.kind = BlogFeedKind.latest,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailure,
    this.depthLimited = false,
  });

  GetBlogsByUserSuccess copyWith({
    List<Blog>? blogs,
    bool? hasMore,
    bool? loadingMore,
    Failure? loadMoreFailure,
    bool? depthLimited,
  }) {
    return GetBlogsByUserSuccess(
      blogs: blogs ?? this.blogs,
      kind: kind,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailure: loadMoreFailure,
      depthLimited: depthLimited ?? this.depthLimited,
    );
  }
}

/// The cross-language list: one row per edition, with the locales the server
/// confirmed it read ([ArticleEditions.locales] may be null on an older
/// deployment, which makes the list current-language only).
final class GetMyArticleEditionsSuccess extends BlogByState {
  final ArticleEditions editions;

  GetMyArticleEditionsSuccess({required this.editions});

  List<Blog> get blogs => editions.blogs;
}

final class GetBlogsByUserLoading extends BlogByState {}

final class GetBlogsByUserFailure extends BlogByState {
  final Failure failure;

  GetBlogsByUserFailure({required this.failure});

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;
}
