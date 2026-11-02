import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/domain/repositories/author_relationship_repository.dart';
import 'package:belog/features/user/domain/usecases/get_author_relationships.dart';
import 'package:belog/features/user/presentation/bloc/author_relationships/author_relationships_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

typedef Result = Either<Failure, List<AuthorRelationship>>;

class DeferredRepository implements AuthorRelationshipRepository {
  final requests = <Completer<Result>>[];
  final arguments = <(String, AuthorRelationshipKind)>[];

  @override
  Future<Result> getRelationships({
    required String userId,
    required AuthorRelationshipKind kind,
  }) {
    arguments.add((userId, kind));
    final request = Completer<Result>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  test(
    'retry replaces a failure, stripping diagnostic causes from UI state',
    () async {
      final repository = DeferredRepository();
      final cubit = AuthorRelationshipsCubit(
        getRelationships: GetAuthorRelationships(repository),
        userId: 'author',
        kind: AuthorRelationshipKind.followers,
      );
      addTearDown(cubit.close);
      repository.requests[0].complete(
        left(Failure.networkOffline(cause: StateError('private'))),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<AuthorRelationshipsFailed>());
      expect((cubit.state as AuthorRelationshipsFailed).failure.cause, isNull);
      final retry = cubit.load();
      expect(cubit.state, isA<AuthorRelationshipsLoading>());
      repository.requests[1].complete(
        right([const AuthorRelationship(userId: 'reader')]),
      );
      await retry;
      expect(
        (cubit.state as AuthorRelationshipsLoaded).people.single.userId,
        'reader',
      );
      expect(repository.arguments, [
        ('author', AuthorRelationshipKind.followers),
        ('author', AuthorRelationshipKind.followers),
      ]);
    },
  );

  test(
    'the latest refresh wins and a closed page ignores late replies',
    () async {
      final repository = DeferredRepository();
      final cubit = AuthorRelationshipsCubit(
        getRelationships: GetAuthorRelationships(repository),
        userId: 'writer',
        kind: AuthorRelationshipKind.following,
      );
      final latest = cubit.load();
      repository.requests[1].complete(
        right([const AuthorRelationship(userId: 'new')]),
      );
      await latest;
      repository.requests[0].complete(left(Failure.networkOffline()));
      await Future<void>.delayed(Duration.zero);
      expect(
        (cubit.state as AuthorRelationshipsLoaded).people.single.userId,
        'new',
      );

      final pending = cubit.load();
      await cubit.close();
      repository.requests[2].complete(
        right([const AuthorRelationship(userId: 'late')]),
      );
      await pending;
      await cubit.load();
      expect(cubit.isClosed, isTrue);
    },
  );
}
