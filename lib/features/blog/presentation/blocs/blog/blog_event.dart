part of 'blog_bloc.dart';

@immutable
sealed class BlogEvent {
  const BlogEvent();
}

/// Loads or reloads page 1 of the feed, replacing the current list.
final class BlogFetchFirstPage extends BlogEvent {
  const BlogFetchFirstPage();
}

/// Appends the next page to the current list. See [BlogBloc] for the guard
/// rules; events that arrive while a request is running are dropped.
final class BlogLoadMore extends BlogEvent {
  const BlogLoadMore();
}
