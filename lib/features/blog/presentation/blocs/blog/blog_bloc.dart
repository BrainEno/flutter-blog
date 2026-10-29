import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'blog_event.dart';
part 'blog_state.dart';

/// Drives the feed list.
///
/// Paging contract:
/// - [BlogFetchFirstPage] replaces the whole list (initial load, refresh,
///   post-publish reload). The newest first-page request always wins: an
///   in-flight older one is discarded via a generation counter, so refresh
///   and load-more can never interleave into a corrupted list.
/// - [BlogLoadMore] appends the next page. It is ignored while another
///   load-more is running (the loading flag is emitted synchronously before
///   the first await), once the end is reached, or without a loaded list.
///   Appends are deduplicated by business id, so page shifts caused by newly
///   published articles cannot produce duplicate cards.
class BlogBloc extends Bloc<BlogEvent, BlogState> {
  final GetAllBlogs _getAllBlogs;

  int _generation = 0;

  BlogBloc({required GetAllBlogs getAllBlogs})
    : _getAllBlogs = getAllBlogs,
      super(const BlogInitial()) {
    on<BlogFetchFirstPage>(_onFetchFirstPage);
    on<BlogLoadMore>(_onLoadMore);
  }

  Future<void> _onFetchFirstPage(
    BlogFetchFirstPage event,
    Emitter<BlogState> emit,
  ) async {
    final generation = ++_generation;
    final previous = state is BlogLoaded ? state as BlogLoaded : null;
    emit(BlogFirstPageLoading(previousBlogs: previous?.blogs ?? const []));
    final res = await _getAllBlogs(const GetAllBlogsParams(page: 1));
    // A newer first-page request (or nothing at all) supersedes this one.
    if (generation != _generation || isClosed) return;
    res.fold(
      (failure) =>
          emit(BlogListFailure(error: failure.message, previousState: state)),
      (blogs) => emit(
        BlogLoaded(
          blogs: blogs,
          page: 1,
          hasReachedMax: blogs.length < kBlogPageSize,
        ),
      ),
    );
  }

  Future<void> _onLoadMore(BlogLoadMore event, Emitter<BlogState> emit) async {
    final current = state;
    if (current is! BlogLoaded ||
        current.isLoadingMore ||
        current.hasReachedMax) {
      return;
    }
    // Synchronous guard: the flag is visible to a concurrently dispatched
    // event before this handler reaches its first await.
    emit(current.copyWith(isLoadingMore: true));
    final generation = _generation;
    final nextPage = current.page + 1;
    final res = await _getAllBlogs(GetAllBlogsParams(page: nextPage));
    // A refresh started while this request was in flight; the fresh first
    // page supersedes anything this response would append.
    if (generation != _generation || isClosed) return;
    final latest = state is BlogLoaded ? state as BlogLoaded : current;
    res.fold(
      (failure) => emit(
        BlogListFailure(
          error: failure.message,
          previousState: latest.copyWith(isLoadingMore: false),
        ),
      ),
      (blogs) {
        if (blogs.isEmpty) {
          emit(latest.copyWith(hasReachedMax: true, isLoadingMore: false));
          return;
        }
        final seen = latest.blogs.map((blog) => blog.id).toSet();
        final fresh = blogs.where((blog) => seen.add(blog.id)).toList();
        emit(
          BlogLoaded(
            blogs: [...latest.blogs, ...fresh],
            page: nextPage,
            hasReachedMax: blogs.length < kBlogPageSize,
          ),
        );
      },
    );
  }
}
