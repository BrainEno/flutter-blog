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

  /// True when a page refreshes after its own toggle rather than because it
  /// shows the saved list; only the latter follows changes made elsewhere.
  final bool afterToggle;

  UserLikedBlogs({required this.userId, this.afterToggle = false});
}

/// Another page saved or unsaved an article for this reader.
final class SavedArticleChangedElsewhere extends BlogLikedEvent {
  final SavedArticleChange change;

  SavedArticleChangedElsewhere(this.change);
}

/// The signed-in account changed: the like state and saved list the bloc
/// holds belong to the previous viewer and must go.
final class BlogLikedSessionChanged extends BlogLikedEvent {
  /// The account signed in now, or null when nobody is.
  final String? viewerId;

  BlogLikedSessionChanged({required this.viewerId});
}
