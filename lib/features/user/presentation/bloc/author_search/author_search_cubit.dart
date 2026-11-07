import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/usecases/browse_authors.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AuthorSearchState {
  const AuthorSearchState();
}

/// Nothing has been asked for yet. The page turns this into the directory on
/// its first frame, so it is only visible for that frame.
final class AuthorSearchInitial extends AuthorSearchState {
  const AuthorSearchInitial();
}

final class AuthorSearchLoading extends AuthorSearchState {
  const AuthorSearchLoading();
}

final class AuthorSearchQueryTooLong extends AuthorSearchState {
  const AuthorSearchQueryTooLong();
}

final class AuthorSearchFailure extends AuthorSearchState {
  const AuthorSearchFailure(this.failure);
  final Failure failure;
}

/// The browsable directory: no query, ordered by reach. It is the answer to an
/// empty field rather than an empty screen.
final class AuthorSearchDirectory extends AuthorSearchState {
  const AuthorSearchDirectory(this.people);
  final List<AuthorSearchResult> people;
}

final class AuthorSearchSuccess extends AuthorSearchState {
  const AuthorSearchSuccess(this.people);
  final List<AuthorSearchResult> people;
}

/// Invalidate immediately on each edit, not only when the debounce timer
/// fires: an old response must not appear under a newer query even briefly.
///
/// The directory is fetched on demand and kept for the life of the cubit, so
/// clearing the field returns to a list the reader already saw instead of
/// flashing a spinner and refetching the same first page.
class AuthorSearchCubit extends Cubit<AuthorSearchState> {
  AuthorSearchCubit({
    required SearchAuthors searchAuthors,
    required BrowseAuthors browseAuthors,
  }) : _searchAuthors = searchAuthors,
       _browseAuthors = browseAuthors,
       super(const AuthorSearchInitial());

  final SearchAuthors _searchAuthors;
  final BrowseAuthors _browseAuthors;
  int _generation = 0;
  List<AuthorSearchResult>? _directory;

  /// Load the directory, or show the cached one. Safe to call repeatedly: an
  /// in-flight reply is dropped if the reader typed in the meantime.
  Future<void> loadDirectory() async {
    if (isClosed) return;
    final cached = _directory;
    if (cached != null) {
      _generation++;
      emit(AuthorSearchDirectory(cached));
      return;
    }
    final generation = ++_generation;
    emit(const AuthorSearchLoading());
    final result = await _browseAuthors();
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(AuthorSearchFailure(failure.forPresentation())),
      (people) => _emitDirectory(people),
    );
  }

  void queryChanged(String input) {
    if (isClosed) return;
    _generation++;
    final query = input.trim();
    if (query.isEmpty) {
      final cached = _directory;
      if (cached == null) {
        unawaited(loadDirectory());
      } else {
        emit(AuthorSearchDirectory(cached));
      }
    } else if (!isValidAuthorSearchQuery(query)) {
      emit(const AuthorSearchQueryTooLong());
    } else {
      emit(const AuthorSearchLoading());
    }
  }

  Future<void> search(String input) async {
    if (isClosed) return;
    final query = input.trim();
    if (query.isEmpty) {
      await loadDirectory();
      return;
    }
    if (!isValidAuthorSearchQuery(query)) {
      queryChanged(input);
      return;
    }
    final generation = ++_generation;
    emit(const AuthorSearchLoading());
    final result = await _searchAuthors(query);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(AuthorSearchFailure(failure.forPresentation())),
      (people) => emit(AuthorSearchSuccess(List.unmodifiable(people))),
    );
  }

  void _emitDirectory(List<AuthorSearchResult> people) {
    final list = List<AuthorSearchResult>.unmodifiable(people);
    _directory = list;
    emit(AuthorSearchDirectory(list));
  }
}
