import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'blog_liked_state.dart';
part 'blog_liked_event.dart';

/// Tracks like status per blog.
///
/// Toggles are serialized per blog: while one request is in flight, further
/// taps on the same blog are queued (odd/even counts naturally cancel out),
/// and every response - the authoritative server-side state, not a blind
/// "success" flag - reconciles the UI. This keeps rapid tapping from
/// double-flipping the server state, and a failed request rolls the icon
/// back to what the server actually has.
class BlogLikedBloc extends Bloc<BlogLikedEvent, BlogLikedState> {
  final ToggleLikeBlog _toggleBlogLike;
  final IsBlogLiked _isBlogLiked;
  final GetUserLikedBlogs _getUserLikedBlogs;

  /// Queued toggles per blog id that have not started a request yet.
  final Map<String, int> _queuedToggles = {};

  /// Whether a toggle drain loop is currently running for a blog id.
  final Map<String, bool> _togglesRunning = {};

  BlogLikedBloc({
    required ToggleLikeBlog toggleBlogLike,
    required IsBlogLiked isBlogLiked,
    required GetUserLikedBlogs getUserLikedBlogs,
  }) : _toggleBlogLike = toggleBlogLike,
       _isBlogLiked = isBlogLiked,
       _getUserLikedBlogs = getUserLikedBlogs,
       super(BlogLikedInitial()) {
    on<GetIsBlogLiked>(_onIsBlogLiked);
    on<ToggleBlogLike>(_onToggleBlogLike);
    on<UserLikedBlogs>(_onGetUserLikedBlogs);
  }

  void _onToggleBlogLike(
    ToggleBlogLike event,
    Emitter<BlogLikedState> emit,
  ) async {
    _queuedToggles[event.blogId] = (_queuedToggles[event.blogId] ?? 0) + 1;
    if (_togglesRunning[event.blogId] ?? false) {
      // A toggle for this blog is already in flight; this one is queued and
      // runs when the current response arrives.
      return;
    }
    _togglesRunning[event.blogId] = true;
    try {
      await _drainToggleQueue(event, emit);
    } finally {
      _togglesRunning[event.blogId] = false;
      if ((_queuedToggles[event.blogId] ?? 0) == 0) {
        _queuedToggles.remove(event.blogId);
      }
    }
  }

  /// Runs queued toggles one at a time so responses cannot arrive out of
  /// order for the same blog.
  Future<void> _drainToggleQueue(
    ToggleBlogLike event,
    Emitter<BlogLikedState> emit,
  ) async {
    // Last known server-side state for this blog. Flip decisions are based
    // on this, not on the (possibly rolled back) UI state, so interleaved
    // emissions cannot corrupt the chain.
    var serverLiked = state.likedBlogs[event.blogId] ?? false;
    var anySuccess = false;

    while ((_queuedToggles[event.blogId] ?? 0) > 0) {
      _queuedToggles[event.blogId] = _queuedToggles[event.blogId]! - 1;

      // Optimistic flip, rendered immediately.
      _emitLiked(emit, event.blogId, !serverLiked);

      final res = await _toggleBlogLike(
        ToggleLikeParams(userId: event.userId, blogId: event.blogId),
      );
      res.fold(
        (failure) {
          // Roll the icon back to the server truth and surface the error;
          // queued taps survive so the user's intent is not lost.
          _emitLiked(emit, event.blogId, serverLiked);
          emit(
            ToggleBlogLikeFailure(
              failure: failure.forPresentation(),
              likedBlogs: state.likedBlogs,
            ),
          );
        },
        (isLiked) {
          // The response is the authoritative post-toggle state.
          serverLiked = isLiked;
          _emitLiked(emit, event.blogId, isLiked);
          anySuccess = true;
        },
      );
    }
    if (anySuccess) {
      // Refresh the collection list once per burst, not once per tap.
      add(UserLikedBlogs(userId: event.userId));
    }
  }

  void _emitLiked(Emitter<BlogLikedState> emit, String blogId, bool isLiked) {
    final updated = Map<String, bool>.from(state.likedBlogs);
    updated[blogId] = isLiked;
    emit(
      ToggleBlogLikeSuccess(
        blogId: blogId,
        isLiked: isLiked,
        likedBlogs: updated,
      ),
    );
  }

  void _onIsBlogLiked(
    GetIsBlogLiked event,
    Emitter<BlogLikedState> emit,
  ) async {
    final res = await _isBlogLiked(
      IsBlogLikedParams(userId: event.userId, blogId: event.blogId),
    );
    res.fold(
      (failure) => emit(
        GetBlogIsLikedFailure(
          failure: failure.forPresentation(),
          likedBlogs: state.likedBlogs,
        ),
      ),
      (isLiked) {
        final updatedLikedBlogs = Map<String, bool>.from(state.likedBlogs);
        updatedLikedBlogs[event.blogId] = isLiked;
        emit(
          GetBlogIsLikedSuccess(
            blogId: event.blogId,
            isLiked: isLiked,
            likedBlogs: updatedLikedBlogs,
          ),
        );
      },
    );
  }

  void _onGetUserLikedBlogs(
    UserLikedBlogs event,
    Emitter<BlogLikedState> emit,
  ) async {
    emit(UserLikedBlogsLoading(likedBlogs: state.likedBlogs));
    final res = await _getUserLikedBlogs(
      GetUserLikedBlogsParams(userId: event.userId),
    );
    res.fold(
      (failure) => emit(
        UserLikedBlogsFailure(
          failure: failure.forPresentation(),
          likedBlogs: state.likedBlogs,
        ),
      ),
      (blogs) {
        final updatedLikedBlogs = Map<String, bool>.from(state.likedBlogs);
        // Reset to avoid stale data.
        updatedLikedBlogs.clear();
        for (var blog in blogs) {
          updatedLikedBlogs[blog.id] = true;
        }
        emit(
          UserLikedBlogsSuccess(blogs: blogs, likedBlogs: updatedLikedBlogs),
        );
      },
    );
  }
}
