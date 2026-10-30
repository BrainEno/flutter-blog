import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';

part 'blog_by_event.dart';
part 'blog_by_state.dart';

class BlogByBloc extends Bloc<BlogByEvent, BlogByState> {
  final GetBlogsByPoster _getBlogsByPoster;

  BlogByBloc({required GetBlogsByPoster getBlogsByPoster})
      : _getBlogsByPoster = getBlogsByPoster,
        super(BlogByInitial()) {
    on<GetBlogByPosterEvent>(_onGetBlogsByPoster);
  }

  void _onGetBlogsByPoster(
      GetBlogByPosterEvent event, Emitter<BlogByState> emit) async {
    emit(GetBlogsByUserLoading());
    final res =
        await _getBlogsByPoster(GetBlogsByPosterParams(userId: event.userId));

    res.fold(
      (failure) => emit(GetBlogsByUserFailure(failure: failure.forPresentation())),
      (blogs) => emit(GetBlogsByUserSuccess(blogs: blogs)),
    );
  }
}
