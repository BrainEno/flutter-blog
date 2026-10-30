import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'recycle_bin_event.dart';
part 'recycle_bin_state.dart';

/// Drives the recycle bin: the author's own tombstones, each restorable
/// until the server sweep purges it.
class RecycleBinBloc extends Bloc<RecycleBinEvent, RecycleBinState> {
  final GetDeletedBlogs _getDeletedBlogs;
  final RestoreDeletedBlog _restoreDeletedBlog;

  RecycleBinBloc({
    required GetDeletedBlogs getDeletedBlogs,
    required RestoreDeletedBlog restoreDeletedBlog,
  }) : _getDeletedBlogs = getDeletedBlogs,
       _restoreDeletedBlog = restoreDeletedBlog,
       super(RecycleBinInitial()) {
    on<RecycleBinRequested>(_onRequested);
    on<RecycleBinRestoreRequested>(_onRestoreRequested);
  }

  Future<void> _onRequested(
    RecycleBinRequested event,
    Emitter<RecycleBinState> emit,
  ) async {
    emit(RecycleBinLoading());
    final res = await _getDeletedBlogs(NoParams());
    res.fold(
      (failure) => emit(RecycleBinFailure(failure.message)),
      (blogs) => emit(RecycleBinSuccess(blogs)),
    );
  }

  Future<void> _onRestoreRequested(
    RecycleBinRestoreRequested event,
    Emitter<RecycleBinState> emit,
  ) async {
    final current = state;
    if (current is! RecycleBinSuccess) return;
    if (current.restoringArticleId != null) return;
    emit(current.copyWith(restoringArticleId: event.articleId));
    final res = await _restoreDeletedBlog(
      RestoreDeletedBlogParams(articleId: event.articleId),
    );
    res.fold(
      (failure) => emit(
        RecycleBinRestoreFailure(
          message: failure.message,
          blogs: current.blogs,
        ),
      ),
      (blog) => emit(
        RecycleBinSuccess(
          current.blogs
              .where((entry) => entry.articleId != event.articleId)
              .toList(),
          lastRestoredTitle: blog.title,
        ),
      ),
    );
  }
}
