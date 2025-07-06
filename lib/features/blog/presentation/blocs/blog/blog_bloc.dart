import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'blog_event.dart';
part 'blog_state.dart';

class BlogBloc extends Bloc<BlogEvent, BlogState> {
  final GetAllBlogs _getAllBlogs;

  BlogBloc({
    required GetAllBlogs getAllBlogs,
  })  : _getAllBlogs = getAllBlogs,
        super(BlogInitial()) {
    on<BlogFetchAllBlogs>(_onFetchAllBlogs);
  }

  void _onFetchAllBlogs(
      BlogFetchAllBlogs event, Emitter<BlogState> emit) async {
    emit(BlogListLoading(previousState: state));
    final res = await _getAllBlogs(GetAllBlogsParams(page: event.page));

    res.fold(
      (failure) => emit(BlogListFailure(error: failure.message,previousState:state)),
      (blogs) => emit(BlogLoaded(
          blogs: event.refresh || state is! BlogLoaded
              ? blogs
              : (state as BlogLoaded).blogs + blogs)),
    );
  }
}
