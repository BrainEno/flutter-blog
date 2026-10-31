import 'dart:io';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'blog_upload_event.dart';
part 'blog_upload_state.dart';

class BlogUploadBloc extends Bloc<BlogUploadEvent, BlogUploadState> {
  final UploadBlog _uploadBlog;
  final UpdateBlog _updateBlog;
  final DeleteBlog _deleteBlog;

  BlogUploadBloc({
    required UploadBlog uploadBlog,
    required UpdateBlog updateBlog,
    required DeleteBlog deleteBlog,
  }) : _uploadBlog = uploadBlog,
       _updateBlog = updateBlog,
       _deleteBlog = deleteBlog,
       super(BlogUploadInitial()) {
    on<UploadBlogEvent>(_onUploadBlog);
    on<UpdateBlogEvent>(_onUpdateBlog);
    on<DeleteBlogEvent>(_onDeleteBlog);
  }

  void _onUploadBlog(
    UploadBlogEvent event,
    Emitter<BlogUploadState> emit,
  ) async {
    emit(BlogUploadLoading());
    final res = await _uploadBlog(
      UploadBlogParams(
        image: event.image,
        title: event.title,
        content: event.content,
        posterId: event.posterId,
        tags: event.tags,
        imageMimeType: event.imageMimeType,
      ),
    );

    res.fold(
      (failure) => emit(BlogUploadFailure(failure.forPresentation())),
      (blog) => emit(BlogUploadSuccess()),
    );
  }

  void _onUpdateBlog(
    UpdateBlogEvent event,
    Emitter<BlogUploadState> emit,
  ) async {
    emit(BlogUploadLoading());
    final res = await _updateBlog(
      UpdateBlogParams(
        blogId: event.blogId,
        image: event.image,
        title: event.title,
        content: event.content,
        tags: event.tags,
        imageMimeType: event.imageMimeType,
      ),
    );
    res.fold(
      (failure) => emit(BlogUploadFailure(failure.forPresentation())),
      (_) => emit(BlogUploadSuccess()),
    );
  }

  void _onDeleteBlog(
    DeleteBlogEvent event,
    Emitter<BlogUploadState> emit,
  ) async {
    emit(BlogDeleteLoading());
    final res = await _deleteBlog(DeleteBlogParams(blogId: event.blogId));
    res.fold(
      (failure) => emit(BlogUploadFailure(failure.forPresentation())),
      (deleted) => deleted
          ? emit(BlogDeleteSuccess())
          : emit(
              BlogUploadFailure(
                Failure('文章未删除，请稍后重试', code: 'article.deleteFailed'),
              ),
            ),
    );
  }
}
