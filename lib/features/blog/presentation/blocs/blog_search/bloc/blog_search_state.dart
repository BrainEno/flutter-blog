part of 'blog_search_bloc.dart';

sealed class BlogSearchState {
  const BlogSearchState();
}

/// Idle: no query entered yet.
class BlogSearchInitial extends BlogSearchState {
  const BlogSearchInitial();
}

class BlogSearchLoading extends BlogSearchState {
  const BlogSearchLoading();
}

class BlogSearchSuccess extends BlogSearchState {
  final List<Blog> blogs;
  BlogSearchSuccess({required this.blogs});
}

class BlogSearchFailure extends BlogSearchState {
  final Failure failure;
  BlogSearchFailure({required this.failure});

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;
}
