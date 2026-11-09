import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/author_articles_paging.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_author_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';

part 'blog_by_event.dart';
part 'blog_by_state.dart';

/// Lists an author's work. Both sources share the same loading/success/failure
/// states because the UI contract is identical; only the scope differs.
class BlogByBloc extends Bloc<BlogByEvent, BlogByState> {
  final GetAuthorArticles _getAuthorArticles;
  final GetMyArticles _getMyArticles;
  final GetMyArticleEditions _getMyArticleEditions;

  /// Which order the author list is in, and which author it belongs to. Held
  /// here so a pending "load more" cannot land on another author's list.
  String? _authorId;

  BlogByBloc({
    required GetAuthorArticles getAuthorArticles,
    required GetMyArticles getMyArticles,
    required GetMyArticleEditions getMyArticleEditions,
  }) : _getAuthorArticles = getAuthorArticles,
       _getMyArticles = getMyArticles,
       _getMyArticleEditions = getMyArticleEditions,
       super(BlogByInitial()) {
    on<GetBlogByPosterEvent>(_onGetBlogsByPoster);
    on<BlogByMoreRequested>(_onMoreRequested);
    on<GetMyArticlesEvent>(_onGetMyArticles);
    on<GetMyArticleEditionsEvent>(_onGetMyArticleEditions);
  }

  Future<void> _onGetBlogsByPoster(
    GetBlogByPosterEvent event,
    Emitter<BlogByState> emit,
  ) async {
    _authorId = event.userId;
    emit(GetBlogsByUserLoading());
    final res = await _getAuthorArticles(
      GetAuthorArticlesParams(userId: event.userId, kind: event.kind),
    );

    res.fold(
      (failure) =>
          emit(GetBlogsByUserFailure(failure: failure.forPresentation())),
      (blogs) => emit(
        GetBlogsByUserSuccess(
          blogs: blogs,
          kind: event.kind,
          hasMore: blogs.length >= kAuthorPageSize,
        ),
      ),
    );
  }

  Future<void> _onMoreRequested(
    BlogByMoreRequested event,
    Emitter<BlogByState> emit,
  ) async {
    final current = state;
    final authorId = _authorId;
    if (current is! GetBlogsByUserSuccess ||
        authorId == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final kind = current.kind;
    final offset = current.blogs.length;
    // The most-saved order is re-ranked while it is read, so the server refuses
    // an offset past its bound and offers no cursor. Asking would only be
    // refused, and a retry could never succeed.
    if (kind == BlogFeedKind.popular && offset > kAuthorPopularMaxOffset) {
      emit(current.copyWith(hasMore: false, depthLimited: true));
      return;
    }
    emit(current.copyWith(loadingMore: true));
    final res = await _getAuthorArticles(
      GetAuthorArticlesParams(userId: authorId, kind: kind, offset: offset),
    );
    // A page that arrives after the reader switched order (or author) must not
    // be appended: its offsets describe a different list.
    final latest = state;
    if (latest is! GetBlogsByUserSuccess ||
        latest.kind != kind ||
        _authorId != authorId) {
      return;
    }
    res.fold(
      (failure) {
        // A refused page is the server saying what the local bound says: this
        // order cannot go deeper. A retry would be refused again.
        if (kind == BlogFeedKind.popular &&
            failure.code == 'server.BAD_USER_INPUT') {
          emit(
            latest.copyWith(
              loadingMore: false,
              hasMore: false,
              depthLimited: true,
            ),
          );
          return;
        }
        emit(
          latest.copyWith(
            loadingMore: false,
            loadMoreFailure: failure.forPresentation(),
          ),
        );
      },
      (more) {
        // Offset paging can repeat a row when something is published while the
        // reader scrolls; ids are stable, so drop what is already shown.
        final seen = latest.blogs.map((blog) => blog.id).toSet();
        final added = more.where((blog) => seen.add(blog.id)).toList();
        emit(
          GetBlogsByUserSuccess(
            blogs: [...latest.blogs, ...added],
            kind: kind,
            hasMore: more.length >= kAuthorPageSize,
          ),
        );
      },
    );
  }

  void _onGetMyArticles(
    GetMyArticlesEvent event,
    Emitter<BlogByState> emit,
  ) async {
    emit(GetBlogsByUserLoading());
    final res = await _getMyArticles(GetMyArticlesParams(userId: event.userId));

    res.fold(
      (failure) =>
          emit(GetBlogsByUserFailure(failure: failure.forPresentation())),
      (blogs) => emit(GetBlogsByUserSuccess(blogs: blogs)),
    );
  }

  void _onGetMyArticleEditions(
    GetMyArticleEditionsEvent event,
    Emitter<BlogByState> emit,
  ) async {
    emit(GetBlogsByUserLoading());
    final res = await _getMyArticleEditions(
      GetMyArticleEditionsParams(userId: event.userId),
    );

    res.fold(
      (failure) =>
          emit(GetBlogsByUserFailure(failure: failure.forPresentation())),
      (editions) => emit(GetMyArticleEditionsSuccess(editions: editions)),
    );
  }
}
