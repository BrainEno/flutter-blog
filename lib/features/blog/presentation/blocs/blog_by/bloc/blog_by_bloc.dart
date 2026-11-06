import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';

part 'blog_by_event.dart';
part 'blog_by_state.dart';

/// Lists an author's work. Both sources share the same loading/success/failure
/// states because the UI contract is identical; only the scope differs.
class BlogByBloc extends Bloc<BlogByEvent, BlogByState> {
  final GetBlogsByPoster _getBlogsByPoster;
  final GetMyArticles _getMyArticles;
  final GetMyArticleEditions _getMyArticleEditions;

  BlogByBloc({
    required GetBlogsByPoster getBlogsByPoster,
    required GetMyArticles getMyArticles,
    required GetMyArticleEditions getMyArticleEditions,
  }) : _getBlogsByPoster = getBlogsByPoster,
       _getMyArticles = getMyArticles,
       _getMyArticleEditions = getMyArticleEditions,
       super(BlogByInitial()) {
    on<GetBlogByPosterEvent>(_onGetBlogsByPoster);
    on<GetMyArticlesEvent>(_onGetMyArticles);
    on<GetMyArticleEditionsEvent>(_onGetMyArticleEditions);
  }

  void _onGetBlogsByPoster(
    GetBlogByPosterEvent event,
    Emitter<BlogByState> emit,
  ) async {
    emit(GetBlogsByUserLoading());
    final res = await _getBlogsByPoster(
      GetBlogsByPosterParams(userId: event.userId),
    );

    res.fold(
      (failure) =>
          emit(GetBlogsByUserFailure(failure: failure.forPresentation())),
      (blogs) => emit(GetBlogsByUserSuccess(blogs: blogs)),
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
