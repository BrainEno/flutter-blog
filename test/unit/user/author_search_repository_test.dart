import 'dart:io';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/user/data/datasources/author_search_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/author_search_repository_impl.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthorSearchRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  late MockRemote remote;
  late MockConnection connection;
  late AuthorSearchRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    repository = AuthorSearchRepositoryImpl(
      remote: remote,
      connectionChecker: connection,
    );
  });

  test('invalid input and offline never masquerade as empty results', () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);
    for (final query in ['', '   ', '🌊' * 51]) {
      final result = await repository.search(query);
      result.fold(
        (failure) => expect(failure.code, 'client.validation'),
        (_) => fail('invalid query must be a failure'),
      );
    }
    final offline = await repository.search('writer');
    offline.fold(
      (failure) => expect(failure.code, 'network.offline'),
      (_) => fail('offline must not look like no matches'),
    );
    verifyNever(() => remote.search(any(), offset: any(named: 'offset')));
  });

  test('an unreadable offset is refused before any request', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    for (final offset in [-1, maxAuthorSearchOffset + 1]) {
      final search = await repository.search('writer', offset: offset);
      search.fold(
        (failure) => expect(failure.code, 'client.validation'),
        (_) => fail('an out-of-range offset must be a failure'),
      );
      final directory = await repository.directory(offset: offset);
      directory.fold(
        (failure) => expect(failure.code, 'client.validation'),
        (_) => fail('an out-of-range offset must be a failure'),
      );
    }
    verifyNever(() => remote.search(any(), offset: any(named: 'offset')));
    verifyNever(() => remote.directory(offset: any(named: 'offset')));
  });

  test(
    'the directory needs no query and stays honest when offline',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      final offline = await repository.directory();
      offline.fold(
        (failure) => expect(failure.code, 'network.offline'),
        (_) => fail('offline must not look like an empty directory'),
      );
      verifyNever(() => remote.directory(offset: any(named: 'offset')));

      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.directory(offset: 0)).thenAnswer(
        (_) async => const [
          AuthorSearchResult(userId: 'one', followerCount: 9, workCount: 4),
        ],
      );
      final success = await repository.directory();
      success.fold(
        (_) => fail('expected success'),
        (people) => expect(people.single.followerCount, 9),
      );
      verify(() => remote.directory(offset: 0)).called(1);
      verifyNever(() => remote.search(any(), offset: any(named: 'offset')));

      when(() => remote.directory(offset: 100)).thenAnswer(
        (_) async => const [AuthorSearchResult(userId: 'two')],
      );
      final deeper = await repository.directory(offset: 100);
      deeper.fold(
        (_) => fail('expected success'),
        (people) => expect(people.single.userId, 'two'),
      );
      verify(() => remote.directory(offset: 100)).called(1);

      when(
        () => remote.directory(offset: 100),
      ).thenThrow(const SocketException('private detail'));
      final error = await repository.directory(offset: 100);
      error.fold(
        (failure) => expect(failure.code, 'network.unavailable'),
        (_) => fail('connection error must be a failure'),
      );
    },
  );

  test(
    'passes the trimmed query, preserves order and maps transport errors',
    () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.search('writer', offset: 0)).thenAnswer(
        (_) async => const [
          AuthorSearchResult(userId: 'one'),
          AuthorSearchResult(userId: 'two'),
        ],
      );
      final success = await repository.search('  writer  ');
      success.fold(
        (_) => fail('expected success'),
        (people) => expect(people.map((p) => p.userId), ['one', 'two']),
      );
      verify(() => remote.search('writer', offset: 0)).called(1);
      when(
        () => remote.search('writer', offset: 0),
      ).thenThrow(const SocketException('private detail'));
      final error = await repository.search('writer');
      error.fold(
        (failure) => expect(failure.code, 'network.unavailable'),
        (_) => fail('connection error must be a failure'),
      );
    },
  );
}
