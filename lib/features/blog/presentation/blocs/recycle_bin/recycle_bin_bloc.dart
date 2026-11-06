import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
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

  /// The account the bin belongs to. Every `/me` route answers for whoever
  /// holds the token, so a bin left open across an account switch would keep
  /// showing - and restoring - the previous account's tombstones (#104).
  final NowaveSessionIdentity? _identity;
  StreamSubscription<void>? _identityChanges;

  /// Whether the page has asked for the bin at least once; a switch only
  /// reloads for a bin that is actually on screen.
  bool _requested = false;

  RecycleBinBloc({
    required GetDeletedBlogs getDeletedBlogs,
    required RestoreDeletedBlog restoreDeletedBlog,
    NowaveSessionIdentity? sessionIdentity,
  }) : _getDeletedBlogs = getDeletedBlogs,
       _restoreDeletedBlog = restoreDeletedBlog,
       _identity = sessionIdentity,
       super(RecycleBinInitial()) {
    on<RecycleBinRequested>(_onRequested);
    on<RecycleBinRestoreRequested>(_onRestoreRequested);
    on<RecycleBinSessionChanged>(_onSessionChanged);
    final identity = sessionIdentity;
    _identityChanges = identity?.identityChanges.listen(
      (_) => add(
        RecycleBinSessionChanged(
          hasOwner: (identity.activeUserId ?? '').isNotEmpty,
        ),
      ),
    );
  }

  int? get _generation => _identity?.sessionGeneration;

  /// Whether a request started under [generation] must be dropped: the
  /// account behind it is no longer the active one.
  bool _isStale(int? generation) =>
      _identity != null && _generation != generation;

  @override
  Future<void> close() async {
    await _identityChanges?.cancel();
    return super.close();
  }

  void _onSessionChanged(
    RecycleBinSessionChanged event,
    Emitter<RecycleBinState> emit,
  ) {
    if (!_requested) return;
    // Drop the previous account's tombstones immediately, then load for
    // whoever is signed in now.
    emit(RecycleBinInitial());
    if (event.hasOwner) add(RecycleBinRequested());
  }

  Future<void> _onRequested(
    RecycleBinRequested event,
    Emitter<RecycleBinState> emit,
  ) async {
    final generation = _generation;
    _requested = true;
    emit(RecycleBinLoading());
    final res = await _getDeletedBlogs(NoParams());
    if (_isStale(generation)) return;
    res.fold(
      (failure) => emit(RecycleBinFailure(failure.forPresentation())),
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
    final generation = _generation;
    emit(current.copyWith(restoringArticleId: event.articleId));
    final res = await _restoreDeletedBlog(
      RestoreDeletedBlogParams(
        articleId: event.articleId,
        locale: event.locale,
      ),
    );
    // The restore was issued for the previous account; its list must not
    // come back for the new one.
    if (_isStale(generation)) return;
    res.fold(
      (failure) => emit(
        RecycleBinRestoreFailure(
          failure: failure.forPresentation(),
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
