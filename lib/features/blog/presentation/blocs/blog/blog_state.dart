part of 'blog_bloc.dart';

@immutable
sealed class BlogState {}

final class BlogInitial extends BlogState {}

final class BlogListLoading extends BlogState {
  final BlogState? previousState;

  BlogListLoading({this.previousState});
}

final class BlogLoaded extends BlogState {
  final List<Blog> blogs;

  BlogLoaded({required this.blogs});
}

final class BlogListFailure extends BlogState {
  final String error;
  final BlogState? previousState;

  BlogListFailure({required this.error,this.previousState});
}
