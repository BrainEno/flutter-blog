import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';

part 'blog_liked_state.dart';
part 'bog_liked_event.dart';

class BlogLikedBloc extends Bloc<BlogLikedEvent, BlogLikedState> {
  final ToggleLikeBlog _toggleBlogLike;
  final IsBlogLiked _isBlogLiked;
  final GetUserLikedBlogs _getUserLikedBlogs;

  BlogLikedBloc({
    required ToggleLikeBlog toggleBlogLike,
    required IsBlogLiked isBlogLiked,
    required GetUserLikedBlogs getUserLikedBlogs,
  })  : _toggleBlogLike = toggleBlogLike,
        _isBlogLiked = isBlogLiked,
        _getUserLikedBlogs = getUserLikedBlogs,
        super(BlogLikedInitial()) {
    on<GetIsBlogLiked>(_onIsBlogLiked);
    on<ToggleBlogLike>(_onToggleBlogLike);
    on<UserLikedBlogs>(_onGetUserLikedBlogs);
  }

  void _onToggleBlogLike(
      ToggleBlogLike event, Emitter<BlogLikedState> emit) async {
    // Get current like status (default to false if unknown)
    final currentLiked = state.likedBlogs[event.blogId] ?? false;
    final newLiked = !currentLiked;

    // Optimistically update the state
    final updatedLikedBlogs = Map<String, bool>.from(state.likedBlogs);
    updatedLikedBlogs[event.blogId] = newLiked;
    emit(ToggleBlogLikeSuccess(
        blogId: event.blogId,
        isLiked: newLiked,
        likedBlogs: updatedLikedBlogs));

    // Perform the toggle operation
    final res = await _toggleBlogLike(
        ToggleLikeParams(userId: event.userId, blogId: event.blogId));
    res.fold(
      (failure) {
        // Preserve previously emitted states and unrelated changes.
        final revertedLikedBlogs = Map<String, bool>.from(state.likedBlogs);
        revertedLikedBlogs[event.blogId] = currentLiked;
        emit(ToggleBlogLikeFailure(
            error: failure.message, likedBlogs: revertedLikedBlogs));
      },
      (result) {
        // Fetch updated list after success
        add(UserLikedBlogs(userId: event.userId));
      },
    );
  }

  void _onIsBlogLiked(
      GetIsBlogLiked event, Emitter<BlogLikedState> emit) async {
    final res = await _isBlogLiked(
        IsBlogLikedParams(userId: event.userId, blogId: event.blogId));
    res.fold(
      (failure) => emit(GetBlogIsLikedFailure(
          error: failure.message, likedBlogs: state.likedBlogs)),
      (isLiked) {
        final updatedLikedBlogs = Map<String, bool>.from(state.likedBlogs);
        updatedLikedBlogs[event.blogId] = isLiked;
        emit(GetBlogIsLikedSuccess(
            blogId: event.blogId,
            isLiked: isLiked,
            likedBlogs: updatedLikedBlogs));
      },
    );
  }

  void _onGetUserLikedBlogs(
      UserLikedBlogs event, Emitter<BlogLikedState> emit) async {
    emit(UserLikedBlogsLoading(likedBlogs: state.likedBlogs));
    final res =
        await _getUserLikedBlogs(GetUserLikedBlogsParams(userId: event.userId));
    res.fold(
      (failure) => emit(UserLikedBlogsFailure(
          error: failure.message, likedBlogs: state.likedBlogs)),
      (blogs) {
        final updatedLikedBlogs = Map<String, bool>.from(state.likedBlogs);
        // Update likedBlogs based on fetched list
        updatedLikedBlogs.clear(); // Reset to avoid stale data
        for (var blog in blogs) {
          updatedLikedBlogs[blog.id] = true;
        }
        emit(
            UserLikedBlogsSuccess(blogs: blogs, likedBlogs: updatedLikedBlogs));
      },
    );
  }
}
