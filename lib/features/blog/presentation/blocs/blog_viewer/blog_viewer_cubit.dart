import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class BlogViewerState {
  const BlogViewerState();
}

final class BlogViewerLoading extends BlogViewerState {
  const BlogViewerLoading();
}

final class BlogViewerLoaded extends BlogViewerState {
  final Blog blog;
  const BlogViewerLoaded(this.blog);
}

final class BlogViewerFailure extends BlogViewerState {
  final String error;
  const BlogViewerFailure(this.error);
}

/// Page-scoped Cubit that resolves the article shown by [BlogViewerPage].
///
/// Cards push the viewer with the already fetched article as `extra`; deep
/// links and state restores only carry the article id and load it here. The
/// Cubit is created and disposed together with the viewer route, so stale
/// articles never leak between pages.
class BlogViewerCubit extends Cubit<BlogViewerState> {
  final GetBlogById _getBlogById;

  BlogViewerCubit({
    required GetBlogById getBlogById,
    required String blogId,
    Blog? initialBlog,
  }) : _getBlogById = getBlogById,
       super(_initialState(initialBlog)) {
    if (initialBlog == null) {
      load(blogId);
    }
  }

  Future<void> load(String blogId) async {
    emit(const BlogViewerLoading());
    final res = await _getBlogById(GetBlogByIdParams(blogId: blogId));
    res.fold(
      (failure) => emit(BlogViewerFailure(failure.message)),
      (blog) => emit(BlogViewerLoaded(blog)),
    );
  }

  static BlogViewerState _initialState(Blog? initialBlog) {
    if (initialBlog == null) {
      return const BlogViewerLoading();
    }
    return BlogViewerLoaded(initialBlog);
  }
}
