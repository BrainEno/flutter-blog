part of 'blog_search_bloc.dart';

sealed class BlogSearchState {}

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
  final String error;
  BlogSearchFailure({required this.error});
}
