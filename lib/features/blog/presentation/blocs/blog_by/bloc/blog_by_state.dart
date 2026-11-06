part of 'blog_by_bloc.dart';

@immutable
sealed class BlogByState {}

final class BlogByInitial extends BlogByState {}

final class GetBlogsByUserSuccess extends BlogByState {
  final List<Blog> blogs;

  GetBlogsByUserSuccess({required this.blogs});
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
