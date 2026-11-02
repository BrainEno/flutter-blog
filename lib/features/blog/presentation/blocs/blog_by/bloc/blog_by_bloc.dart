import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
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

  BlogByBloc({
    required GetBlogsByPoster getBlogsByPoster,
    required GetMyArticles getMyArticles,
  }) : _getBlogsByPoster = getBlogsByPoster,
       _getMyArticles = getMyArticles,
       super(BlogByInitial()) {
    on<GetBlogByPosterEvent>(_onGetBlogsByPoster);
    on<GetMyArticlesEvent>(_onGetMyArticles);
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
}
