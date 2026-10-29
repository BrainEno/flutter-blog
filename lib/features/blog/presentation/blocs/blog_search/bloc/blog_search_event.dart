part of 'blog_search_bloc.dart';

sealed class BlogSearchEvent {
  const BlogSearchEvent();
}

/// Searches blogs whose title contains [query]. Whitespace-only queries are
/// treated like a clear.
class SearchBlogsEvent extends BlogSearchEvent {
  final String query;

  const SearchBlogsEvent({required this.query});
}

/// Resets the search to its idle state, discarding any in-flight response.
class SearchBlogsCleared extends BlogSearchEvent {
  const SearchBlogsCleared();
}
