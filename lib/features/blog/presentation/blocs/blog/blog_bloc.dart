import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'blog_event.dart';
part 'blog_state.dart';

/// Drives the selected feed. Refreshes, feed changes and identity changes
/// invalidate older requests; load-more never mixes sources or feed kinds.
class BlogBloc extends Bloc<BlogEvent, BlogState> {
  final GetAllBlogs _getAllBlogs;

  int _generation = 0;
  BlogFeedKind _kind = BlogFeedKind.latest;
  String? _viewerId;

  /// The bound the API puts on a `sort=popular` offset. It is a constructor
  /// argument only so a test can reach the bound in a few pages; callers take
  /// the API's own number.
  final int popularMaxOffset;

  BlogBloc({
    required GetAllBlogs getAllBlogs,
    this.popularMaxOffset = kPopularFeedMaxOffset,
  }) : _getAllBlogs = getAllBlogs,
       super(const BlogInitial()) {
    on<BlogFetchFirstPage>(_onFetchFirstPage);
    on<BlogLoadMore>(_onLoadMore);
    on<BlogViewerChanged>(_onViewerChanged);
  }

  Future<void> _onFetchFirstPage(
    BlogFetchFirstPage event,
    Emitter<BlogState> emit,
  ) async {
    final kind = event.kind ?? _kind;
    final viewerId = kind == BlogFeedKind.following
        ? (event.kind == null ? _viewerId : event.viewerId)
        : null;
    final selectionChanged = kind != _kind || viewerId != _viewerId;
    _kind = kind;
    _viewerId = viewerId;
    final generation = ++_generation;

    // Keep content for a refresh of the same list only. A different tab or
    // account must never temporarily display the previous selection's data.
    emit(
      BlogFirstPageLoading(
        kind: kind,
        viewerId: viewerId,
        previousBlogs: selectionChanged ? const [] : _previousBlogs(state),
        previousSource: selectionChanged ? null : _previousSource(state),
      ),
    );
    if (kind == BlogFeedKind.following &&
        (viewerId == null || viewerId.isEmpty)) {
      emit(
        BlogListFailure(
          kind: kind,
          viewerId: viewerId,
          failure: Failure.auth('请先登录账户'),
        ),
      );
      return;
    }
    final res = await _getAllBlogs(
      GetAllBlogsParams(page: 1, kind: kind, expectedViewerId: viewerId),
    );
    if (generation != _generation) return;
    res.fold(
      (failure) => emit(
        BlogListFailure(
          kind: kind,
          viewerId: viewerId,
          failure: failure.forPresentation(),
          previousState: state,
        ),
      ),
      (result) {
        if (kind != BlogFeedKind.latest &&
            result.source != BlogFeedSource.network) {
          emit(
            BlogListFailure(
              kind: kind,
              viewerId: viewerId,
              failure: const Failure(
                '文章来源已变化，请刷新后重试',
                code: 'feed.sourceChanged',
              ),
            ),
          );
          return;
        }
        emit(
          BlogLoaded(
            kind: kind,
            viewerId: viewerId,
            blogs: result.blogs,
            source: result.source,
            page: 1,
            hasReachedMax: result.blogs.length < kBlogPageSize,
            nextCursor:
                kind == BlogFeedKind.latest &&
                    result.source == BlogFeedSource.network
                ? result.nextCursor
                : null,
          ),
        );
      },
    );
  }

  void _onViewerChanged(BlogViewerChanged event, Emitter<BlogState> emit) {
    if (_kind != BlogFeedKind.following || event.viewerId == _viewerId) return;
    // Invalidate in-flight first/load-more requests before clearing private
    // follow relationships. A new default feed is fetched independently.
    _generation++;
    _kind = BlogFeedKind.latest;
    _viewerId = null;
    emit(const BlogInitial());
    add(const BlogFetchFirstPage());
  }

  List<Blog> _previousBlogs(BlogState current) {
    if (current is BlogLoaded) return current.blogs;
    if (current is BlogFirstPageLoading) return current.previousBlogs;
    if (current is BlogListFailure && current.previousState != null) {
      return _previousBlogs(current.previousState!);
    }
    return const [];
  }

  BlogFeedSource? _previousSource(BlogState current) {
    if (current is BlogLoaded) return current.source;
    if (current is BlogFirstPageLoading) return current.previousSource;
    if (current is BlogListFailure && current.previousState != null) {
      return _previousSource(current.previousState!);
    }
    return null;
  }

  Future<void> _onLoadMore(BlogLoadMore event, Emitter<BlogState> emit) async {
    final current = state;
    if (current is! BlogLoaded ||
        current.isLoadingMore ||
        current.hasReachedMax) {
      return;
    }
    final generation = _generation;
    final nextPage = current.page + 1;
    // The most-saved order is re-ranked while it is read, so it has no cursor
    // and the server refuses an offset past its bound. Asking would only be
    // refused, and a retry could never succeed: stop here and let the list say
    // where the reader can keep reading instead.
    if (current.kind == BlogFeedKind.popular &&
        (nextPage - 1) * kBlogPageSize > popularMaxOffset) {
      emit(
        current.copyWith(
          hasReachedMax: true,
          isLoadingMore: false,
          depthLimited: true,
        ),
      );
      return;
    }
    // Synchronous guard before the first await.
    emit(current.copyWith(isLoadingMore: true));
    final res = await _getAllBlogs(
      GetAllBlogsParams(
        page: nextPage,
        source: current.source,
        kind: current.kind,
        expectedViewerId: current.viewerId,
        cursor:
            current.kind == BlogFeedKind.latest &&
                current.source == BlogFeedSource.network
            ? current.nextCursor
            : null,
      ),
    );
    if (generation != _generation) return;
    final latest = state is BlogLoaded ? state as BlogLoaded : current;
    res.fold(
      (failure) {
        // A refused page is the server saying what the local bound says: this
        // order cannot go deeper. A retry would be refused again, so the list
        // stops with the explanation instead of an error the reader can only
        // repeat.
        if (latest.kind == BlogFeedKind.popular &&
            failure.code == 'server.BAD_USER_INPUT') {
          emit(
            latest.copyWith(
              hasReachedMax: true,
              isLoadingMore: false,
              depthLimited: true,
            ),
          );
          return;
        }
        emit(
          BlogListFailure(
            kind: latest.kind,
            viewerId: latest.viewerId,
            failure: failure.forPresentation(),
            previousState: latest.copyWith(isLoadingMore: false),
          ),
        );
      },
      (result) {
        // Never combine offsets from two different data sources.
        if (result.source != latest.source) {
          emit(
            BlogListFailure(
              kind: latest.kind,
              viewerId: latest.viewerId,
              failure: const Failure(
                '文章来源已变化，请刷新后重试',
                code: 'feed.sourceChanged',
              ),
              previousState: latest.copyWith(isLoadingMore: false),
            ),
          );
          return;
        }
        final blogs = result.blogs;
        if (blogs.isEmpty) {
          emit(latest.copyWith(hasReachedMax: true, isLoadingMore: false));
          return;
        }
        final seen = latest.blogs.map((blog) => blog.id).toSet();
        final fresh = blogs.where((blog) => seen.add(blog.id)).toList();
        emit(
          BlogLoaded(
            kind: latest.kind,
            viewerId: latest.viewerId,
            blogs: [...latest.blogs, ...fresh],
            source: latest.source,
            page: nextPage,
            hasReachedMax: blogs.length < kBlogPageSize,
            nextCursor:
                latest.kind == BlogFeedKind.latest &&
                    result.source == BlogFeedSource.network
                ? result.nextCursor
                : null,
          ),
        );
      },
    );
  }
}
