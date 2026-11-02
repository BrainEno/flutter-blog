import 'dart:io';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/user/data/datasources/author_relationship_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/author_relationship_repository_impl.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthorRelationshipRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  late MockRemote remote;
  late MockConnection connection;
  late AuthorRelationshipRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    repository = AuthorRelationshipRepositoryImpl(
      remote: remote,
      connectionChecker: connection,
    );
  });

  test('offline is explicit and never returns a fabricated list', () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);
    final result = await repository.getRelationships(
      userId: 'author',
      kind: AuthorRelationshipKind.followers,
    );
    result.fold(
      (failure) => expect(failure.code, 'network.offline'),
      (_) => fail('offline must not look like an empty list'),
    );
    verifyNever(
      () => remote.getRelationships(
        userId: 'author',
        kind: AuthorRelationshipKind.followers,
      ),
    );
  });

  test(
    'returns server data in order and classifies connection errors',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.getRelationships(
          userId: 'author',
          kind: AuthorRelationshipKind.following,
        ),
      ).thenAnswer(
        (_) async => const [
          AuthorRelationship(userId: 'one'),
          AuthorRelationship(userId: 'two'),
        ],
      );
      final success = await repository.getRelationships(
        userId: 'author',
        kind: AuthorRelationshipKind.following,
      );
      success.fold(
        (_) => fail('expected success'),
        (people) =>
            expect(people.map((person) => person.userId), ['one', 'two']),
      );
      when(
        () => remote.getRelationships(
          userId: 'author',
          kind: AuthorRelationshipKind.following,
        ),
      ).thenThrow(const SocketException('private detail'));
      final failure = await repository.getRelationships(
        userId: 'author',
        kind: AuthorRelationshipKind.following,
      );
      failure.fold(
        (error) => expect(error.code, 'network.unavailable'),
        (_) => fail('network error must not be a successful list'),
      );
    },
  );
}
