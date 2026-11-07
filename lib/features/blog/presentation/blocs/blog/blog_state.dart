part of 'blog_bloc.dart';

@immutable
sealed class BlogState {
  const BlogState({this.kind = BlogFeedKind.latest, this.viewerId});

  /// The selected list. A following list is tied to [viewerId] and must
  /// never be rendered for a different or signed-out viewer.
  final BlogFeedKind kind;
  final String? viewerId;
}

final class BlogInitial extends BlogState {
  const BlogInitial();
}

/// A first page is loading. [previousBlogs] keeps the last rendered list
/// during refresh, but is empty when changing feed or account.
final class BlogFirstPageLoading extends BlogState {
  final List<Blog> previousBlogs;
  final BlogFeedSource? previousSource;

  const BlogFirstPageLoading({
    super.kind,
    super.viewerId,
    this.previousBlogs = const [],
    this.previousSource,
  });
}

/// The feed list. [page] is the last appended page, [hasReachedMax] stops
/// further automatic loading and [isLoadingMore] drives the bottom spinner.
final class BlogLoaded extends BlogState {
  final List<Blog> blogs;
  final BlogFeedSource source;
  final int page;
  final bool hasReachedMax;
  final bool isLoadingMore;

  /// The list ended because the order itself has no deeper page, not because
  /// the reader ran out of works. The most-saved order is bounded
  /// ([kPopularFeedMaxOffset]) and has no cursor, so the footer explains where
  /// the reader can continue instead of claiming there is nothing more.
  final bool depthLimited;

  /// Local continuation for this latest/network session, or null for offset.
  final String? nextCursor;

  const BlogLoaded({
    super.kind,
    super.viewerId,
    required this.blogs,
    required this.source,
    required this.page,
    required this.hasReachedMax,
    this.isLoadingMore = false,
    this.depthLimited = false,
    this.nextCursor,
  });

  BlogLoaded copyWith({
    List<Blog>? blogs,
    BlogFeedSource? source,
    int? page,
    bool? hasReachedMax,
    bool? isLoadingMore,
    bool? depthLimited,
  }) {
    return BlogLoaded(
      kind: kind,
      viewerId: viewerId,
      blogs: blogs ?? this.blogs,
      source: source ?? this.source,
      page: page ?? this.page,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      depthLimited: depthLimited ?? this.depthLimited,
      nextCursor: nextCursor,
    );
  }
}

/// A request failed. [previousState] preserves the same feed's last list so
/// a transient error does not discard already rendered content.
final class BlogListFailure extends BlogState {
  final Failure failure;
  final BlogState? previousState;

  const BlogListFailure({
    super.kind,
    super.viewerId,
    required this.failure,
    this.previousState,
  });

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;
}
