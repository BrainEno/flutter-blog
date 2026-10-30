part of 'blog_liked_bloc.dart';

@immutable
sealed class BlogLikedEvent {}

final class ToggleBlogLike extends BlogLikedEvent {
  final String userId;
  final String blogId;

  ToggleBlogLike({required this.userId, required this.blogId});
}

final class GetIsBlogLiked extends BlogLikedEvent {
  final String userId;
  final String blogId;

  GetIsBlogLiked({required this.userId, required this.blogId});
}

final class UserLikedBlogs extends BlogLikedEvent {
  final String userId;

  UserLikedBlogs({required this.userId});
}
