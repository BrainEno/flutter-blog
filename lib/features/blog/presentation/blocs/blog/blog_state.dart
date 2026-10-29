part of 'blog_bloc.dart';

@immutable
sealed class BlogState {}

final class BlogInitial extends BlogState {
  const BlogInitial();
}

/// A first page is loading. [previousBlogs] keeps the last rendered list so
/// pull-to-refresh and post-publish reloads do not blank the feed.
final class BlogFirstPageLoading extends BlogState {
  final List<Blog> previousBlogs;

  const BlogFirstPageLoading({this.previousBlogs = const []});
}

/// The feed list. [page] is the last appended page, [hasReachedMax] stops
/// further automatic loading and [isLoadingMore] drives the bottom spinner.
final class BlogLoaded extends BlogState {
  final List<Blog> blogs;
  final int page;
  final bool hasReachedMax;
  final bool isLoadingMore;

  const BlogLoaded({
    required this.blogs,
    required this.page,
    required this.hasReachedMax,
    this.isLoadingMore = false,
  });

  BlogLoaded copyWith({
    List<Blog>? blogs,
    int? page,
    bool? hasReachedMax,
    bool? isLoadingMore,
  }) {
    return BlogLoaded(
      blogs: blogs ?? this.blogs,
      page: page ?? this.page,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// A request failed. [previousState] preserves the last list so the feed can
/// keep showing cached content with an error hint instead of a dead spinner.
final class BlogListFailure extends BlogState {
  final String error;
  final BlogState? previousState;

  const BlogListFailure({required this.error, this.previousState});
}
