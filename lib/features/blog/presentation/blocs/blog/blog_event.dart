part of 'blog_bloc.dart';

@immutable
sealed class BlogEvent {
  const BlogEvent();
}

/// Loads page 1. Omit [kind] to refresh the current list; selecting a new
/// kind discards the old list. A following request must supply its viewer.
final class BlogFetchFirstPage extends BlogEvent {
  const BlogFetchFirstPage({this.kind, this.viewerId})
    : assert(kind != BlogFeedKind.following || viewerId != null);

  final BlogFeedKind? kind;
  final String? viewerId;
}

/// Invalidates a following feed when the signed-in identity changes.
final class BlogViewerChanged extends BlogEvent {
  const BlogViewerChanged(this.viewerId);

  final String? viewerId;
}

/// Appends the next page to the current list. Events that arrive while a
/// request is running, after the end, or without a loaded list are dropped.
final class BlogLoadMore extends BlogEvent {
  const BlogLoadMore();
}
