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

/// A list that has been read: the browsable directory or the matches for a
/// query. Both page the same way, because both are the same endpoint.
sealed class AuthorSearchList extends AuthorSearchState {
  const AuthorSearchList(
    this.people, {
    this.nextOffset = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreFailure,
  });

  final List<AuthorSearchResult> people;

  /// Rows consumed so far, which is the `offset` of the next page. It counts
  /// rows received, not rows kept, so de-duplication cannot make paging skip.
  final int nextOffset;

  /// The last page was full and the API's own offset bound has not been
  /// reached, so asking for another page can still return rows.
  final bool hasMore;

  final bool isLoadingMore;

  /// A failed *next* page. The rows already read stay on screen; only the
  /// footer changes.
  final Failure? loadMoreFailure;
}

/// The browsable directory: no query, ordered by reach. It is the answer to an
/// empty field rather than an empty screen.
final class AuthorSearchDirectory extends AuthorSearchList {
  const AuthorSearchDirectory(
    super.people, {
    super.nextOffset,
    super.hasMore,
    super.isLoadingMore,
    super.loadMoreFailure,
  });
}

final class AuthorSearchSuccess extends AuthorSearchList {
  const AuthorSearchSuccess(
    super.people, {
    super.nextOffset,
    super.hasMore,
    super.isLoadingMore,
    super.loadMoreFailure,
  });
}

/// Invalidate immediately on each edit, not only when the debounce timer
/// fires: an old response must not appear under a newer query even briefly.
///
/// The directory is fetched on demand and kept for the life of the cubit, so
/// clearing the field returns to a list the reader already saw - including the
/// pages they paged through - instead of flashing a spinner and refetching.
class AuthorSearchCubit extends Cubit<AuthorSearchState> {
  AuthorSearchCubit({
    required SearchAuthors searchAuthors,
    required BrowseAuthors browseAuthors,
    this.maxOffset = maxAuthorSearchOffset,
  }) : _searchAuthors = searchAuthors,
       _browseAuthors = browseAuthors,
       super(const AuthorSearchInitial());

  final SearchAuthors _searchAuthors;
  final BrowseAuthors _browseAuthors;

  /// The API's bound on the directory's offset. A constructor argument only so
  /// a test can reach the bound in a few pages; callers take the API's number.
  final int maxOffset;
  int _generation = 0;

  /// The query the list on screen answers; `''` is the directory.
  String _query = '';

  /// The directory is kept whole, so leaving a search returns to the same
  /// rows rather than to the first page of them.
  List<AuthorSearchResult>? _directory;
  int _directoryOffset = 0;
  bool _directoryHasMore = false;

  /// Load the directory's first page, or show the cached one. Safe to call
  /// repeatedly: an in-flight reply is dropped if the reader typed meanwhile.
  Future<void> loadDirectory() async {
    if (isClosed) return;
    _query = '';
    final cached = _directory;
    if (cached != null) {
      _generation++;
      emit(
        AuthorSearchDirectory(
          cached,
          nextOffset: _directoryOffset,
          hasMore: _directoryHasMore,
        ),
      );
      return;
    }
    final generation = ++_generation;
    emit(const AuthorSearchLoading());
    final result = await _browseAuthors();
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(AuthorSearchFailure(failure.forPresentation())),
      (people) => _emitDirectory(people, nextOffset: people.length),
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
        _query = '';
        emit(
          AuthorSearchDirectory(
            cached,
            nextOffset: _directoryOffset,
            hasMore: _directoryHasMore,
          ),
        );
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
    _query = query;
    emit(const AuthorSearchLoading());
    final result = await _searchAuthors(query);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(AuthorSearchFailure(failure.forPresentation())),
      (people) => emit(
        AuthorSearchSuccess(
          _freeze(people),
          nextOffset: people.length,
          hasMore: _canPageFurther(people.length, people.length),
        ),
      ),
    );
  }

  /// Fetch the next page of whatever list is on screen.
  ///
  /// Ignored when a page is already in flight, when the last page was short,
  /// when the API's offset bound is reached, or after an edit invalidated the
  /// list this page belonged to.
  Future<void> loadMore() async {
    if (isClosed) return;
    final current = state;
    if (current is! AuthorSearchList ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }
    final query = _query;
    final offset = current.nextOffset;
    final generation = _generation;
    emit(
      _copyWith(
        current,
        people: current.people,
        nextOffset: current.nextOffset,
        hasMore: current.hasMore,
        isLoadingMore: true,
        loadMoreFailure: null,
      ),
    );
    final result = query.isEmpty
        ? await _browseAuthors(offset: offset)
        : await _searchAuthors(query, offset: offset);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) {
        final base = _visible(current);
        emit(
          _copyWith(
            base,
            people: base.people,
            nextOffset: base.nextOffset,
            hasMore: base.hasMore,
            isLoadingMore: false,
            loadMoreFailure: failure.forPresentation(),
          ),
        );
      },
      (people) {
        final base = _visible(current);
        final seen = base.people.map((person) => person.userId).toSet();
        final fresh = people.where((person) => seen.add(person.userId));
        final merged = _freeze([...base.people, ...fresh]);
        final consumed = base.nextOffset + people.length;
        final hasMore = _canPageFurther(people.length, consumed);
        if (query.isEmpty) {
          _directory = merged;
          _directoryOffset = consumed;
          _directoryHasMore = hasMore;
          emit(
            AuthorSearchDirectory(
              merged,
              nextOffset: consumed,
              hasMore: hasMore,
            ),
          );
          return;
        }
        emit(
          AuthorSearchSuccess(merged, nextOffset: consumed, hasMore: hasMore),
        );
      },
    );
  }

  /// A full page means the list may continue, but never past the API's bound.
  bool _canPageFurther(int pageLength, int consumed) =>
      pageLength == maxAuthorSearchResults && consumed <= maxOffset;

  void _emitDirectory(
    List<AuthorSearchResult> people, {
    required int nextOffset,
  }) {
    final list = _freeze(people);
    final hasMore = _canPageFurther(people.length, nextOffset);
    _directory = list;
    _directoryOffset = nextOffset;
    _directoryHasMore = hasMore;
    emit(AuthorSearchDirectory(list, nextOffset: nextOffset, hasMore: hasMore));
  }

  /// The list to append to: the one on screen, or the page that was requested
  /// if the state moved on (a failure never discards the rows already read).
  AuthorSearchList _visible(AuthorSearchList requested) {
    final current = state;
    return current is AuthorSearchList ? current : requested;
  }

  AuthorSearchList _copyWith(
    AuthorSearchList current, {
    required List<AuthorSearchResult> people,
    required int nextOffset,
    required bool hasMore,
    required bool isLoadingMore,
    required Failure? loadMoreFailure,
  }) => switch (current) {
    AuthorSearchDirectory() => AuthorSearchDirectory(
      people,
      nextOffset: nextOffset,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      loadMoreFailure: loadMoreFailure,
    ),
    AuthorSearchSuccess() => AuthorSearchSuccess(
      people,
      nextOffset: nextOffset,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      loadMoreFailure: loadMoreFailure,
    ),
  };

  List<AuthorSearchResult> _freeze(List<AuthorSearchResult> people) =>
      List<AuthorSearchResult>.unmodifiable(people);
}
