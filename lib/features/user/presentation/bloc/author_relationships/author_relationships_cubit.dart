import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/domain/usecases/get_author_relationships.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AuthorRelationshipsState {
  const AuthorRelationshipsState();
}

final class AuthorRelationshipsLoading extends AuthorRelationshipsState {
  const AuthorRelationshipsLoading();
}

final class AuthorRelationshipsFailed extends AuthorRelationshipsState {
  const AuthorRelationshipsFailed(this.failure);
  final Failure failure;
}

final class AuthorRelationshipsLoaded extends AuthorRelationshipsState {
  const AuthorRelationshipsLoaded(this.people);
  final List<AuthorRelationship> people;
}

/// Scoped to one author and relation. A later refresh supersedes an earlier
/// result, including a late failure; closing the page ignores late replies.
class AuthorRelationshipsCubit extends Cubit<AuthorRelationshipsState> {
  AuthorRelationshipsCubit({
    required GetAuthorRelationships getRelationships,
    required this.userId,
    required this.kind,
  }) : _getRelationships = getRelationships,
       super(const AuthorRelationshipsLoading()) {
    load();
  }

  final GetAuthorRelationships _getRelationships;
  final String userId;
  final AuthorRelationshipKind kind;
  int _generation = 0;

  Future<void> load() async {
    if (isClosed) return;
    final generation = ++_generation;
    emit(const AuthorRelationshipsLoading());
    final result = await _getRelationships(userId: userId, kind: kind);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(AuthorRelationshipsFailed(failure.forPresentation())),
      (people) => emit(AuthorRelationshipsLoaded(List.unmodifiable(people))),
    );
  }
}
