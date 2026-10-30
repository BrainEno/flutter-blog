part of 'blog_by_bloc.dart';

@immutable
sealed class BlogByState {}

final class BlogByInitial extends BlogByState {}

final class GetBlogsByUserSuccess extends BlogByState {
  final List<Blog> blogs;

  GetBlogsByUserSuccess({required this.blogs});
}

final class GetBlogsByUserLoading extends BlogByState {}

final class GetBlogsByUserFailure extends BlogByState {
  final Failure failure;

  GetBlogsByUserFailure({required this.failure});

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;
}
