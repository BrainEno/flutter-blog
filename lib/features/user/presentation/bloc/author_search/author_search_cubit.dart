import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AuthorSearchState {
  const AuthorSearchState();
}

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

final class AuthorSearchSuccess extends AuthorSearchState {
  const AuthorSearchSuccess(this.people);
  final List<AuthorSearchResult> people;
}

/// Invalidate immediately on each edit, not only when the debounce timer
/// fires: an old response must not appear under a newer query even briefly.
class AuthorSearchCubit extends Cubit<AuthorSearchState> {
  AuthorSearchCubit({required SearchAuthors searchAuthors})
    : _searchAuthors = searchAuthors,
      super(const AuthorSearchInitial());

  final SearchAuthors _searchAuthors;
  int _generation = 0;

  void queryChanged(String input) {
    if (isClosed) return;
    _generation++;
    final query = input.trim();
    if (query.isEmpty) {
      emit(const AuthorSearchInitial());
    } else if (!isValidAuthorSearchQuery(query)) {
      emit(const AuthorSearchQueryTooLong());
    } else {
      emit(const AuthorSearchLoading());
    }
  }

  Future<void> search(String input) async {
    if (isClosed) return;
    final query = input.trim();
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
}
